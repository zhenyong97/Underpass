import Foundation
import SystemConfiguration
import Darwin

struct SessionPlan {
    let id: UUID
    let directory: URL
    let relayPort: Int
    let mixedPort: Int
    let apiPort: Int
    let secret: String
    let fingerprint: String
    let protocolName: String
    let initialRevision: String
}
struct RuleRevision {
    var token: String
    var route: Data
    var dns: Data
    static func make(_ packages: [ChannelPackage], token: String = UUID().uuidString.lowercased()) throws -> Self {
        var route: [[String: Any]] = [], dns: [[String: Any]] = []
        for p in packages {
            if !p.match.domains.isEmpty { route.append(["domain": p.match.domains]) }
            if !p.match.domainSuffixes.isEmpty { route.append(["domain_suffix": p.match.domainSuffixes]) }
            if !p.match.processNames.isEmpty { route.append(["process_name": p.match.processNames]) }
            if !p.match.applicationPaths.isEmpty { route.append(["process_path_regex": p.match.applicationPaths.map { "^" + NSRegularExpression.escapedPattern(for: $0) + "/Contents/" }]) }
            if p.dns == "node" {
                if !p.match.domains.isEmpty { dns.append(["domain": p.match.domains]) }
                if !p.match.domainSuffixes.isEmpty { dns.append(["domain_suffix": p.match.domainSuffixes]) }
            }
        }
        route.append(["domain": [token + ".route.underpass.invalid"]])
        dns.append(["domain": [token + ".dns.underpass.invalid"]])
        func encode(_ rules: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: ["version": 3, "rules": rules], options: [.sortedKeys]) }
        return try Self(token: token, route: encode(route), dns: encode(dns))
    }
    func write(to directory: URL) throws {
        try RuntimeIO.secureWrite(route, to: directory.appendingPathComponent("active-route.json"))
        try RuntimeIO.secureWrite(dns, to: directory.appendingPathComponent("active-dns.json"))
    }
}

enum EngineConfiguration {
    // Preserve supported original proxy paths rather than silently forcing unrelated sites to the node.
    static func fallback(v2Port: Int) throws -> String {
        try fallback(settings: SCDynamicStoreCopyProxies(nil) as? [String: Any] ?? [:], v2Port: v2Port)
    }
    static func fallback(settings: [String: Any], v2Port: Int) throws -> String {
        if (settings["ProxyAutoConfigEnable"] as? Int == 1) || (settings["ProxyAutoDiscoveryEnable"] as? Int == 1) {
            throw UnderpassError.message("当前使用 PAC 或自动发现代理，尚不能保持其逐站规则。请先在 v2rayN 中选择系统代理模式后开启。")
        }
        var active = false
        for prefix in ["HTTP", "HTTPS", "SOCKS"] where settings[prefix + "Enable"] as? Int == 1 {
            active = true
            guard settings[prefix + "Proxy"] as? String == "127.0.0.1", settings[prefix + "Port"] as? Int == v2Port else {
                throw UnderpassError.message("当前系统代理由另一个会话或工具接管。请先关闭旧音乐通道或其他代理接管，再手动开启暗渡。")
            }
        }
        return active ? "existing-v2rayn" : "direct"
    }
    static func sourceInfo(_ source: URL = RuntimeIO.sourceConfig) throws -> (String, Int) {
        let original = try RuntimeIO.object(source)
        guard let inbounds = original["inbounds"] as? [[String: Any]],
              let port = inbounds.first(where: { ["mixed", "socks"].contains($0["protocol"] as? String ?? "") })?["port"] as? Int,
              (1025...65535).contains(port),
              let outputs = original["outbounds"] as? [[String: Any]],
              let proto = outputs.first(where: { $0["tag"] as? String == "proxy" })?["protocol"] as? String,
              ["vless", "vmess", "trojan", "shadowsocks", "socks", "http"].contains(proto) else {
            throw UnderpassError.message("未找到支持的 Xray 节点；请先在 v2rayN 中启动节点。")
        }
        return (proto.uppercased(), port)
    }
    static func makePlan(source: URL = RuntimeIO.sourceConfig, base: URL, relayPort: Int, mixedPort: Int, apiPort: Int, dns: String, packages: [ChannelPackage], fallback: String = "existing-v2rayn", pid: Int32 = getpid()) throws -> SessionPlan {
        let data = try Data(contentsOf: source), info = try sourceInfo(source)
        guard let original = try JSONSerialization.jsonObject(with: data) as? [String: Any], let outputs = original["outbounds"] as? [[String: Any]] else { throw UnderpassError.message("节点配置无效。") }
        guard Set([relayPort, mixedPort, apiPort]).count == 3, [relayPort, mixedPort, apiPort].allSatisfy({ (1025...65535).contains($0) }), ["existing-v2rayn", "direct"].contains(fallback) else { throw UnderpassError.message("会话端口或回退路径无效。") }
        for p in packages { try p.validate() }
        let id = UUID(), session = base.appendingPathComponent(id.uuidString, isDirectory: true)
        try RuntimeIO.fm.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let user = "underpass", password = UUID().uuidString, secret = UUID().uuidString + UUID().uuidString
            guard let interface = (83...199).map({ "utun\($0)" }).first(where: { name in name.withCString { if_nametoindex($0) == 0 } }) else { throw UnderpassError.message("没有可用的 TUN 网卡。") }
            let xray: [String: Any] = [
                "log": ["loglevel": "warning"], "dns": ["servers": ["localhost"]],
                "inbounds": [["listen": "127.0.0.1", "port": relayPort, "protocol": "socks", "tag": "underpass-only", "settings": ["auth": "password", "accounts": [["user": user, "pass": password]], "udp": true]]],
                "outbounds": outputs,
                "routing": ["domainStrategy": "AsIs", "rules": [["type": "field", "inboundTag": ["underpass-only"], "outboundTag": "proxy"]]]
            ]
            let revision = try RuleRevision.make(packages)
            try revision.write(to: session)
            let sb: [String: Any] = [
                "log": ["level": "info", "timestamp": true],
                "dns": ["servers": [
                    ["type": "udp", "tag": "original-dns", "server": dns],
                    ["type": "https", "tag": "node-dns", "server": "1.12.12.12", "server_port": 443, "path": "/dns-query", "tls": ["enabled": true, "server_name": "doh.pub"], "detour": "selected-node"]
                ], "rules": [
                    ["type": "logical", "mode": "and", "rules": [["domain_suffix": ["route.underpass.invalid"]], ["rule_set": ["active-route"]]], "action": "predefined", "rcode": "NOERROR"],
                    ["type": "logical", "mode": "and", "rules": [["domain_suffix": ["dns.underpass.invalid"]], ["rule_set": ["active-dns"]]], "action": "predefined", "rcode": "NOERROR"],
                    ["domain_suffix": ["underpass.invalid"], "action": "predefined", "rcode": "NXDOMAIN"],
                    ["rule_set": ["active-dns"], "server": "node-dns"]
                ], "final": "original-dns", "strategy": "prefer_ipv4", "independent_cache": true, "reverse_mapping": true],
                "inbounds": [
                    ["type": "tun", "tag": "underpass-tun", "interface_name": interface, "address": ["172.30.83.1/30", "fd83:6d75:7369::1/126"], "mtu": 1500, "auto_route": true, "strict_route": false, "stack": "system"],
                    ["type": "mixed", "tag": "system-proxy", "listen": "127.0.0.1", "listen_port": mixedPort]
                ],
                "outbounds": [
                    ["type": "socks", "tag": "selected-node", "server": "127.0.0.1", "server_port": relayPort, "version": "5", "username": user, "password": password],
                    ["type": "socks", "tag": "existing-v2rayn", "server": "127.0.0.1", "server_port": info.1, "version": "5"],
                    ["type": "direct", "tag": "direct"]
                ],
                "route": ["auto_detect_interface": true, "default_domain_resolver": "original-dns", "rules": [
                    ["process_name": ["xray", "sing-box", "underpass-helper"], "action": "route", "outbound": "direct"],
                    ["action": "sniff", "timeout": "300ms"],
                    ["protocol": "dns", "action": "hijack-dns"], ["port": 53, "action": "hijack-dns"],
                    ["rule_set": ["active-route"], "action": "route", "outbound": "selected-node"],
                    ["ip_is_private": true, "action": "route", "outbound": "direct"],
                    ["inbound": ["system-proxy"], "action": "route", "outbound": fallback]
                ], "final": "direct", "rule_set": [
                    ["type": "local", "tag": "active-route", "format": "source", "path": session.appendingPathComponent("active-route.json").path],
                    ["type": "local", "tag": "active-dns", "format": "source", "path": session.appendingPathComponent("active-dns.json").path]
                ]],
                "experimental": ["clash_api": ["external_controller": "127.0.0.1:\(apiPort)", "secret": secret, "default_mode": "rule"]]
            ]
            try RuntimeIO.jsonWrite(xray, to: session.appendingPathComponent("xray.json"))
            try RuntimeIO.jsonWrite(sb, to: session.appendingPathComponent("sing-box.json"))
            try RuntimeIO.jsonWrite(["parentPID": pid, "ownerUID": getuid(), "mixedPort": mixedPort, "relayPort": relayPort, "apiPort": apiPort, "sourceHash": RuntimeIO.hash(data), "sourcePath": source.path, "fallback": fallback, "existingPort": info.1, "sessionID": id.uuidString, "created": Date().timeIntervalSince1970], to: session.appendingPathComponent("session.json"))
            for name in ["heartbeat", "helper.log", "xray.log", "sing-box.log", "status.json", "original-proxy.json", "dns-flushed"] { try RuntimeIO.secureWrite(Data(), to: session.appendingPathComponent(name)) }
            return SessionPlan(id: id, directory: session, relayPort: relayPort, mixedPort: mixedPort, apiPort: apiPort, secret: secret, fingerprint: RuntimeIO.hash(data), protocolName: info.0, initialRevision: revision.token)
        } catch { try? RuntimeIO.fm.removeItem(at: session); throw error }
    }
    static func validate(_ plan: SessionPlan, binaries: URL) throws {
        let x = try RuntimeIO.run(binaries.appendingPathComponent("xray"), ["run", "-test", "-c", plan.directory.appendingPathComponent("xray.json").path])
        guard x.0 == 0 else { throw UnderpassError.message("节点配置校验失败，请在 v2rayN 中重选节点。") }
        let s = try RuntimeIO.run(binaries.appendingPathComponent("sing-box"), ["check", "-c", plan.directory.appendingPathComponent("sing-box.json").path])
        guard s.0 == 0 else { throw UnderpassError.message("通道配置校验失败。请检查通道规则与内核版本。") }
    }
}
