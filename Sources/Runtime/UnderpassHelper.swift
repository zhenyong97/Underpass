import Foundation
import SystemConfiguration
import Darwin

private var stopping: sig_atomic_t = 0
private func handleSignal(_ signal: Int32) { stopping = 1 }

func safeWrite(_ text: String, to url: URL) throws {
    let fd = open(url.path, O_WRONLY | O_TRUNC | O_NOFOLLOW)
    guard fd >= 0 else { throw UnderpassError.message("无法写入运行状态。") }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    try handle.write(contentsOf: Data(text.utf8))
    try handle.close()
}

final class ProxyLease {
    let preferences: SCPreferences
    let proto: SCNetworkProtocol
    let serviceID: String
    let original: [String: Any]
    let port: Int
    var applied = false
    let networkFingerprint: String
    init(port: Int, session: URL) throws {
        guard let store = SCDynamicStoreCreate(nil, "Underpass" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let id = global["PrimaryService"] as? String,
              let prefs = SCPreferencesCreate(nil, "Underpass" as CFString, nil),
              let service = SCNetworkServiceCopy(prefs, id as CFString),
              let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else {
            throw UnderpassError.message("无法识别当前网络服务，请先连接网络。")
        }
        self.preferences = prefs; self.proto = proto; self.serviceID = id; self.port = port
        self.original = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
        self.networkFingerprint = Self.fingerprint(store, id: id)
        let backup: [String: Any] = ["serviceID": id, "configuration": original, "port": port]
        let data = try JSONSerialization.data(withJSONObject: backup, options: [.sortedKeys])
        try safeWrite(String(decoding: data, as: UTF8.self), to: session.appendingPathComponent("original-proxy.json"))
    }
    func apply() throws {
        var settings = original
        let enabled = ["HTTP", "HTTPS", "SOCKS"].filter { original[$0 + "Enable"] as? Int == 1 }
        for prefix in enabled.isEmpty ? ["HTTP", "HTTPS"] : enabled {
            settings[prefix + "Enable"] = 1
            settings[prefix + "Proxy"] = "127.0.0.1"
            settings[prefix + "Port"] = port
        }
        settings["ProxyAutoConfigEnable"] = 0; settings["ProxyAutoDiscoveryEnable"] = 0
        applied = true // A partial commit must also be restored.
        guard SCNetworkProtocolSetConfiguration(proto, settings as CFDictionary),
              SCPreferencesCommitChanges(preferences), SCPreferencesApplyChanges(preferences) else {
            throw UnderpassError.message("系统代理切换失败，将恢复原设置。")
        }
    }
    func restore() -> Bool {
        guard applied else { return true }
        SCPreferencesSynchronize(preferences)
        guard let service = SCNetworkServiceCopy(preferences, serviceID as CFString),
              let currentProto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else { return false }
        var current = SCNetworkProtocolGetConfiguration(currentProto) as? [String: Any] ?? [:]
        guard let restored = ProxyRestoration.restored(current: current, original: original, port: port) else { applied = false; return true }
        current = restored
        let result = SCNetworkProtocolSetConfiguration(currentProto, current as CFDictionary)
            && SCPreferencesCommitChanges(preferences) && SCPreferencesApplyChanges(preferences)
        if result { applied = false }
        return result
    }
    func networkChanged() -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "Underpass" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return true }
        return global["PrimaryService"] as? String != serviceID || Self.fingerprint(store, id: serviceID) != networkFingerprint
    }
    static func fingerprint(_ store: SCDynamicStore, id: String) -> String {
        let value = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(id)/IPv4" as CFString) as? [String: Any] ?? [:]
        let dns = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(id)/DNS" as CFString) as? [String: Any] ?? [:]
        return String(describing: value["Addresses"] ?? "") + String(describing: value["Router"] ?? "") + String(describing: value["InterfaceName"] ?? "") + String(describing: dns["ServerAddresses"] ?? "")
    }

}

func launchCore(_ binary: URL, args: [String], log: URL) throws -> Process {
    let fd = open(log.path, O_WRONLY | O_APPEND | O_NOFOLLOW)
    guard fd >= 0 else { throw UnderpassError.message("无法打开内核日志。") }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    let process = Process()
    process.executableURL = binary; process.arguments = args
    process.standardOutput = handle; process.standardError = handle
    try process.run()
    try? handle.close()
    return process
}

func stopCore(_ process: Process?) {
    guard let process, process.isRunning else { return }
    process.terminate()
    for _ in 0..<30 { if !process.isRunning { return }; Thread.sleep(forTimeInterval: 0.1) }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
}

func supervise(session: URL, binaries: URL) throws {
    guard getuid() == 0 else { throw UnderpassError.message("需要 macOS 管理员授权。") }
    let metadata = try RuntimeIO.object(session.appendingPathComponent("session.json"))
    guard let owner = metadata["ownerUID"] as? UInt32,
          let parent = metadata["parentPID"] as? Int32,
          let mixed = metadata["mixedPort"] as? Int,
          let relay = metadata["relayPort"] as? Int,
          let api = metadata["apiPort"] as? Int,
          mixed > 1024, relay > 1024, api > 1024, parent > 1 else { throw UnderpassError.message("运行会话无效。") }
    var statbuf = stat()
    guard lstat(session.path, &statbuf) == 0, statbuf.st_uid == owner,
          (statbuf.st_mode & S_IFMT) == S_IFDIR, statbuf.st_mode & 0o077 == 0 else {
        throw UnderpassError.message("运行目录权限不正确。")
    }
    let lockFD = open(session.deletingLastPathComponent().appendingPathComponent("supervisor.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
    guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw UnderpassError.message("暗渡已有运行会话。请先关闭另一个暗渡窗口中的通道。") }
    defer { flock(lockFD, LOCK_UN); close(lockFD) }
    var corePIDs: [String: Int32] = [:]
    let status = session.appendingPathComponent("status.json")
    func publish(_ state: String, _ message: String) {
        if let data = try? JSONSerialization.data(withJSONObject: ["state": state, "message": message, "helperPID": getpid(), "corePIDs": corePIDs, "sessionID": metadata["sessionID"] ?? ""]) {
            try? safeWrite(String(decoding: data, as: UTF8.self), to: status)
        }
    }
    signal(SIGTERM, handleSignal); signal(SIGINT, handleSignal); signal(SIGHUP, handleSignal)
    var xray: Process?, tun: Process?, lease: ProxyLease?
    var failure: String?
    defer {
        // Restore the proxy while its listener is still available, then close the TUN.
        let restored = lease?.restore() ?? true
        stopCore(tun); stopCore(xray)
        if !restored { publish("error", "自动恢复系统代理失败。请在系统网络设置中关闭指向本工具的本机代理。") }
        else if let failure { publish("error", failure) }
        else { publish("stopped", "通道已关闭，原系统代理已恢复。") }
        // Node credentials and authentication tokens are transient.
        for name in ["xray.json", "sing-box.json"] { try? FileManager.default.removeItem(at: session.appendingPathComponent(name)) }
    }
    do {
        guard kill(parent, 0) == 0, !FileManager.default.fileExists(atPath: session.appendingPathComponent("stop").path) else { return }
        let heartbeat = try? FileManager.default.attributesOfItem(atPath: session.appendingPathComponent("heartbeat").path)[.modificationDate] as? Date
        guard let heartbeat, Date().timeIntervalSince(heartbeat) < 12 else { throw UnderpassError.message("启动请求已过期，请重新开启。") }
        publish("starting", "正在建立专用通道。")
        lease = try ProxyLease(port: mixed, session: session)
        guard let expectedFallback = metadata["fallback"] as? String, let existingPort = metadata["existingPort"] as? Int,
              try EngineConfiguration.fallback(settings: lease!.original, v2Port: existingPort) == expectedFallback else { throw UnderpassError.message("等待授权期间原系统代理已改变，请重新开启通道。") }
        if let path = metadata["sourcePath"] as? String, let hash = metadata["sourceHash"] as? String,
           (try? Data(contentsOf: URL(fileURLWithPath: path))).map(RuntimeIO.hash) != hash { throw UnderpassError.message("等待授权期间节点已变化，请重新开启通道。") }
        xray = try launchCore(binaries.appendingPathComponent("xray"), args: ["run", "-c", session.appendingPathComponent("xray.json").path], log: session.appendingPathComponent("xray.log"))
        corePIDs["xray"] = xray?.processIdentifier
        for _ in 0..<50 {
            if RuntimeIO.portOpen(relay) { break }
            guard xray?.isRunning == true else { throw UnderpassError.message("专用节点内核启动失败，请查看诊断日志。") }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard RuntimeIO.portOpen(relay) else { throw UnderpassError.message("专用节点端口启动超时。") }
        tun = try launchCore(binaries.appendingPathComponent("sing-box"), args: ["run", "-c", session.appendingPathComponent("sing-box.json").path], log: session.appendingPathComponent("sing-box.log"))
        corePIDs["sing-box"] = tun?.processIdentifier
        for _ in 0..<80 {
            if RuntimeIO.portOpen(api), RuntimeIO.portOpen(mixed) { break }
            guard tun?.isRunning == true else { throw UnderpassError.message("TUN 启动失败。请关闭其他 TUN/VPN 接管后重试，或查看诊断日志。") }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard RuntimeIO.portOpen(api), RuntimeIO.portOpen(mixed), tun?.isRunning == true else { throw UnderpassError.message("TUN 通道启动超时。") }
        guard kill(parent, 0) == 0, !FileManager.default.fileExists(atPath: session.appendingPathComponent("stop").path) else { return }
        guard lease?.networkChanged() == false else { throw UnderpassError.message("启动期间网络已切换，请重新开启通道。") }
        try lease?.apply()
        publish("ready", "内核已就绪；规则确认后可验证网页与实际播放。")
        while stopping == 0 {
            if FileManager.default.fileExists(atPath: session.appendingPathComponent("stop").path) { break }
            if kill(parent, 0) != 0 { break }
            let heartbeat = try? FileManager.default.attributesOfItem(atPath: session.appendingPathComponent("heartbeat").path)[.modificationDate] as? Date
            if heartbeat == nil || Date().timeIntervalSince(heartbeat!) > 12 { break }
            guard xray?.isRunning == true, tun?.isRunning == true else { throw UnderpassError.message("代理内核意外退出，已撤销通道。") }
            if let path = metadata["sourcePath"] as? String, let hash = metadata["sourceHash"] as? String,
               (try? Data(contentsOf: URL(fileURLWithPath: path))).map(RuntimeIO.hash) != hash { throw UnderpassError.message("v2rayN 节点配置已变化，已停止旧会话。请手动重新开启。") }
            if lease?.networkChanged() == true { throw UnderpassError.message("当前网络已切换，通道已关闭。请在新网络上重新开启。") }
            let flush = session.appendingPathComponent("dns-flush")
            if let token = try? String(contentsOf: flush, encoding: .utf8), !token.isEmpty, token.count < 100 {
                let cache = try? RuntimeIO.run(URL(fileURLWithPath: "/usr/bin/dscacheutil"), ["-flushcache"])
                let responder = try? RuntimeIO.run(URL(fileURLWithPath: "/usr/bin/killall"), ["-HUP", "mDNSResponder"])
                if cache?.0 == 0 && responder?.0 == 0 { try? safeWrite(token, to: session.appendingPathComponent("dns-flushed")) }
                try? FileManager.default.removeItem(at: flush)
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    } catch { failure = error.localizedDescription }
}

func recover(session: URL, binaries: URL) throws {
    guard getuid() == 0 else { throw UnderpassError.message("恢复需要管理员授权。") }
    let meta = try RuntimeIO.object(session.appendingPathComponent("session.json"))
    var info = stat()
    guard let owner = meta["ownerUID"] as? UInt32, lstat(session.path, &info) == 0, info.st_uid == owner, info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else { throw UnderpassError.message("恢复目录权限无效。") }
    if let state = try? RuntimeIO.object(session.appendingPathComponent("status.json")), let pid = state["helperPID"] as? Int32, pid > 1, kill(pid, 0) == 0 { throw UnderpassError.message("助手仍在运行，请先关闭通道并等待自动恢复。") }
    let backup = try RuntimeIO.object(session.appendingPathComponent("original-proxy.json"))
    guard let id = backup["serviceID"] as? String, let original = backup["configuration"] as? [String: Any], let port = backup["port"] as? Int,
          let prefs = SCPreferencesCreate(nil, "Underpass Recovery" as CFString, nil), let service = SCNetworkServiceCopy(prefs, id as CFString), let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else { throw UnderpassError.message("没有可恢复的原代理快照。") }
    let current = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
    if let restored = ProxyRestoration.restored(current: current, original: original, port: port) {
        guard SCNetworkProtocolSetConfiguration(proto, restored as CFDictionary), SCPreferencesCommitChanges(prefs), SCPreferencesApplyChanges(prefs) else { throw UnderpassError.message("恢复系统代理失败，请在系统网络设置中检查。") }
    }
    if let state = try? RuntimeIO.object(session.appendingPathComponent("status.json")), let pids = state["corePIDs"] as? [String: Int32] {
        for name in ["sing-box", "xray"] {
            guard let pid = pids[name], pid > 1 else { continue }
            let command = (try? RuntimeIO.run(URL(fileURLWithPath: "/bin/ps"), ["-p", String(pid), "-o", "command="]).1.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            let expected = binaries.appendingPathComponent(name).path + " run -c " + session.appendingPathComponent(name == "xray" ? "xray.json" : "sing-box.json").path
            if command == expected {
                kill(pid, SIGTERM)
                for _ in 0..<30 { if kill(pid, 0) != 0 { break }; Thread.sleep(forTimeInterval: 0.1) }
                let remaining = (try? RuntimeIO.run(URL(fileURLWithPath: "/bin/ps"), ["-p", String(pid), "-o", "command="]).1.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                if remaining == expected { kill(pid, SIGKILL) }
            }
        }
    }
    try safeWrite("{\"state\":\"stopped\",\"message\":\"原代理快照已恢复。\"}", to: session.appendingPathComponent("status.json"))
    for name in ["xray.json", "sing-box.json"] { try? FileManager.default.removeItem(at: session.appendingPathComponent(name)) }
}

@main struct HelperMain {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard args.count == 3, ["--session", "--recover"].contains(args[1]) else { throw UnderpassError.message("此程序由 Underpass 管理。") }
            let executable = URL(fileURLWithPath: args[0]).standardizedFileURL
            if args[1] == "--recover" { try recover(session: URL(fileURLWithPath: args[2]), binaries: executable.deletingLastPathComponent()) }
            else { try supervise(session: URL(fileURLWithPath: args[2]), binaries: executable.deletingLastPathComponent()) }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
