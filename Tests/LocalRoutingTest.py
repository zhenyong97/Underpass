"""Bundled sing-box integration. Loopback only: no TUN, system proxy or Internet.
Tests atomic local-rule reloads, real DNS routing/cache, TLS CONNECT, affected
connection closing and an unchanged other-service connection. Not a playback test.
"""
import http.client, json, os, pathlib, socket, ssl, struct, subprocess, tempfile, threading, time

PROJECT = pathlib.Path(__file__).resolve().parents[1]
CORE = PROJECT / 'outputs/暗渡.app/Contents/Helpers/sing-box'
PROBE = PROJECT / '.build/engine-probe'
checks = 0

def listener():
    s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); return s

def port():
    s=listener(); p=s.getsockname()[1]; s.close(); return p

def exact(s,n):
    data=b''
    while len(data)<n:
        part=s.recv(n-len(data))
        if not part: raise EOFError()
        data+=part
    return data

def dns_response(query, ip):
    end=12
    while query[end]: end += query[end]+1
    end += 5
    question=query[12:end]
    return query[:2]+b'\x81\x80'+b'\x00\x01\x00\x01\x00\x00\x00\x00'+question+b'\xc0\x0c'+b'\x00\x01\x00\x01\x00\x00\x00\x3c\x00\x04'+socket.inet_aton(ip)

def udp_dns(sock):
    while True:
        try:
            data, addr=sock.recvfrom(4096); sock.sendto(dns_response(data,'192.0.2.2'),addr)
        except OSError: return

def serve_client(c,label,tls):
    try:
        c.settimeout(8)
        h=exact(c,2); exact(c,h[1]); c.sendall(b'\x05\x00')
        req=exact(c,4)
        if req[3]==3: host=exact(c,exact(c,1)[0]).decode()
        elif req[3]==1: host=socket.inet_ntoa(exact(c,4))
        else: host=socket.inet_ntop(socket.AF_INET6,exact(c,16))
        target_port=struct.unpack('!H',exact(c,2))[0]
        c.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x01')
        if c.recv(1,socket.MSG_PEEK)==b'\x16': c=tls.wrap_socket(c,server_side=True)
        data=b''
        while b'\r\n\r\n' not in data: data+=c.recv(4096)
        head,body=data.split(b'\r\n\r\n',1)
        length=0
        for line in head.split(b'\r\n')[1:]:
            if line.lower().startswith(b'content-length:'): length=int(line.split(b':',1)[1])
        if length>len(body): body+=exact(c,length-len(body))
        if b'/dns-query' in head.split(b'\r\n')[0]:
            payload=dns_response(body,'192.0.2.1'); content_type=b'application/dns-message'
        else: payload=label.encode(); content_type=b'text/plain'
        hold=b'/hold' in head.split(b'\r\n')[0]
        c.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: '+content_type+b'\r\nContent-Length: '+str(len(payload)+(1024 if hold else 0)).encode()+b'\r\nConnection: '+(b'keep-alive' if hold else b'close')+b'\r\n\r\n'+payload)
        if hold:
            while c.recv(4096): pass
    except (OSError,EOFError,ValueError): pass
    finally: c.close()

def serve(sock,label,tls):
    while True:
        try: c,_=sock.accept()
        except OSError: return
        threading.Thread(target=serve_client,args=(c,label,tls),daemon=True).start()

with tempfile.TemporaryDirectory(prefix='underpass-loopback-',dir=PROJECT/'.build') as temp:
    root=pathlib.Path(temp)
    subprocess.run([str(PROJECT/'.build/core-tests'),str(PROJECT),'--emit-fixture',str(root)],check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['/usr/bin/openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(root/'key.pem'),'-out',str(root/'cert.pem'),'-subj','/CN=offline.test','-days','1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); tls.load_cert_chain(root/'cert.pem',root/'key.pem')
    node,existing=listener(),listener()
    for s,label in [(node,'node'),(existing,'existing')]: threading.Thread(target=serve,args=(s,label,tls),daemon=True).start()
    dns=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);dns.bind(('127.0.0.1',0));threading.Thread(target=udp_dns,args=(dns,),daemon=True).start()
    mixed,api=port(),port()
    cfg=json.loads((root/'config.json').read_text())
    cfg['inbounds']=[dict(type='mixed',tag='system-proxy',listen='127.0.0.1',listen_port=mixed)]
    cfg['outbounds'][0]=dict(type='socks',tag='selected-node',server='127.0.0.1',server_port=node.getsockname()[1],version='5')
    cfg['outbounds'][1]=dict(type='socks',tag='existing-v2rayn',server='127.0.0.1',server_port=existing.getsockname()[1],version='5')
    cfg['dns']['servers']=[dict(type='udp',tag='original-dns',server='127.0.0.1',server_port=dns.getsockname()[1]),dict(type='https',tag='node-dns',server='127.0.0.1',server_port=443,path='/dns-query',tls=dict(enabled=True,insecure=True),detour='selected-node')]
    cfg['experimental']['clash_api']=dict(external_controller=f'127.0.0.1:{api}',secret='offline-test-only')
    (root/'config.json').write_text(json.dumps(cfg))
    subprocess.run([str(CORE),'check','-c',str(root/'config.json')],check=True)
    log=(root/'core.log').open('w'); core=subprocess.Popen([str(CORE),'run','-c',str(root/'config.json')],stdout=log,stderr=log)
    def call(path,method='GET'):
        c=http.client.HTTPConnection('127.0.0.1',api,timeout=5)
        try:
            c.request(method,path,headers={'Authorization':'Bearer offline-test-only'});r=c.getresponse();data=r.read();assert r.status in (200,204),(path,r.status,data)
            return json.loads(data) if data else None
        finally: c.close()
    def probe(mode,value):
        r=subprocess.run([str(PROBE),str(api),str(root),mode,str(value)],capture_output=True,text=True,timeout=15)
        assert r.returncode==0,r.stderr[-2000:]
    def set_rules(label):
        for name in ['active-route.json','active-dns.json']:
            staged=root/(name+'.tmp');staged.write_bytes((root/label/name).read_bytes());os.replace(staged,root/name)
        probe('confirm',(root/label/'token').read_text())
    def request(host,secure=False):
        c=http.client.HTTPSConnection('127.0.0.1',mixed,timeout=5,context=ssl._create_unverified_context()) if secure else http.client.HTTPConnection('127.0.0.1',mixed,timeout=5)
        try:
            if secure: c.set_tunnel(host,443); c.request('GET','/',headers={'Host':host,'Connection':'close'})
            else: c.request('GET','http://'+host+'/',headers={'Host':host,'Connection':'close'})
            r=c.getresponse(); assert r.status==200; return r.read().decode()
        finally: c.close()
    def dns_query(host):
        result=call('/dns/query?name='+host+'&type=A');assert result.get('Answer'),(host,result);return result['Answer'][0]['data'].strip()
    def hold(host):
        c=socket.create_connection(('127.0.0.1',mixed),timeout=5);c.sendall(f'GET http://{host}/hold HTTP/1.1\r\nHost: {host}\r\n\r\n'.encode());assert b'200 OK' in c.recv(4096);return c
    try:
        for _ in range(50):
            if core.poll() is not None: raise RuntimeError((root/'core.log').read_text())
            try: call('/version');break
            except OSError: time.sleep(.1)
        for label,qq,bili in [('10',True,False),('11',True,True),('01',False,True),('00',False,False)]:
            set_rules(label)
            cases=[('y.qq.com',qq),('www.bilibili.com',bili),('api.bilibili.com',bili),('upos-sz-mirror.bilivideo.com',bili),('i0.hdslb.com',bili),('example.com',False),('bilibili.com.example.org',False)]
            for secure in [False,True]:
                for host,enabled in cases:
                    actual=request(host,secure);assert actual==('node' if enabled else 'existing'),(label,host,secure,actual);checks+=1
            for host,enabled in [('y.qq.com',qq),('api.bilibili.com',bili),('example.com',False)]:
                actual=dns_query(host);assert actual==('192.0.2.1' if enabled else '192.0.2.2'),(label,host,actual);checks+=1
            print(f'PASS {label}: atomic hot reload + HTTP/TLS domains + original/node DNS selection')
        set_rules('11')
        held_bili=hold('www.bilibili.com');held_qq=hold('y.qq.com');time.sleep(.1)
        connections=call('/connections')['connections'];bili_ids={c['id'] for c in connections if c['metadata'].get('host')=='www.bilibili.com'};qq_ids={c['id'] for c in connections if c['metadata'].get('host')=='y.qq.com'}
        assert bili_ids and qq_ids, connections
        set_rules('01');probe('settle',PROJECT/'Resources/Channels/01-qqmusic.channel.json')
        after={c['id'] for c in call('/connections')['connections']};assert bili_ids<=after and not qq_ids&after;checks+=1
        held_bili.close();held_qq.close()
        set_rules('dynamic');assert request('third.example.com')=='node';assert request('y.qq.com')=='existing';checks+=2
        # A malformed file must not replace the kernel's last valid rules.
        (root/'active-route.json').write_text('{broken');time.sleep(.4)
        assert request('third.example.com')=='node';checks+=1
        set_rules('01');assert request('third.example.com')=='existing';assert request('www.bilibili.com')=='node';checks+=2
        # Explicit core DNS flush removes a previously cached answer across a switch.
        assert dns_query('api.bilibili.com')=='192.0.2.1';set_rules('00');call('/cache/dns/flush','POST');assert dns_query('api.bilibili.com')=='192.0.2.2';checks+=1
        print(f'PASS: {checks} integration assertions; same sing-box PID throughout, affected connections closed and other service retained')
        print('Scope: loopback HTTP, TLS CONNECT and synthetic UDP/DoH DNS; no real TUN/process capture, QUIC, system authorization or media playback.')
    finally:
        core.terminate()
        try:core.wait(timeout=4)
        except subprocess.TimeoutExpired:core.kill();core.wait()
        node.close();existing.close();dns.close();log.close()
