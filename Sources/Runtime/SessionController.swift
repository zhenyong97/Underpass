import Foundation
import Combine
import AppKit

@MainActor final class SessionController: ObservableObject {
    @Published private(set) var active: [ChannelPackage] = []
    @Published private(set) var busy = false
    @Published private(set) var message = "开启服务时需要 macOS 管理员授权。"
    @Published private(set) var failure: String?
    @Published private(set) var connections: [EngineConnection] = []
    @Published private(set) var plan: SessionPlan?
    private var authorization: Process?
    private var exitResult: (Int32, Bool)?
    private var revision: RuleRevision?
    private var gate = SessionGate()
    private var timer: Timer?
    private var monitoring = false
    private var stopping = false
    var binaries: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers") }
    var sessionsBase: URL { ChannelStore.defaultDirectory.appendingPathComponent("Sessions") }
    var hasSession: Bool { authorization != nil }
    init(monitor: Bool = true) {
        if monitor { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in await self?.tick() } } }
    }
    func apply(_ packages: [ChannelPackage]) async throws {
        guard !busy else { throw UnderpassError.message("正在应用上一项操作，请稍候。") }
        if let failure, hasSession { throw UnderpassError.message(failure) }
        busy = true; failure = nil
        defer { busy = false }
        if packages.isEmpty {
            try await stop(); return
        }
        if !hasSession { try await start(packages); return }
        guard let plan, let old = revision else { throw UnderpassError.message("共享会话尚未就绪。") }
        let next = try RuleRevision.make(packages)
        let changed = active.filter { previous in !packages.contains(previous) } + packages.filter { p in !active.contains(p) }
        message = "正在应用规则并刷新 DNS；受影响的旧连接将重新建立。"
        do {
            try await RuleTransaction.apply(next, replacing: old, directory: plan.directory, runtime: EngineClient(plan: plan), affected: changed)
            guard gate.accepts(plan.id), hasSession, status(plan)?["state"] as? String == "ready" else { throw UnderpassError.message("更新期间会话已结束。") }
            revision = next; active = packages; message = "内核与规则已确认；请重开应用或网页后验证播放。"
        } catch {
            if error is RuleRollbackError { try? await stop() }
            failure = error.localizedDescription; throw error
        }
    }
    private func start(_ packages: [ChannelPackage]) async throws {
        let info = try EngineConfiguration.sourceInfo()
        guard RuntimeIO.portOpen(info.1) else { throw UnderpassError.message("v2rayN 节点端口未运行。请先启动节点。") }
        if let gui = try? RuntimeIO.object(RuntimeIO.v2Directory.appendingPathComponent("guiConfigs/guiNConfig.json")), let tun = gui["TunModeItem"] as? [String: Any], tun["EnableTun"] as? Bool == true { throw UnderpassError.message("请先关闭 v2rayN 的 TUN 模式，保留节点运行。") }
        let fallback = try EngineConfiguration.fallback(v2Port: info.1)
        message = "正在校验节点；随后 macOS 将请求管理员授权。"
        let base = sessionsBase, binaries = binaries
        let prepared = try await Task.detached(priority: .userInitiated) {
            var ports = Set<Int>(); while ports.count < 3 { ports.insert(try RuntimeIO.availablePort()) }
            let v = ports.sorted()
            let p = try EngineConfiguration.makePlan(base: base, relayPort: v[0], mixedPort: v[1], apiPort: v[2], dns: RuntimeIO.detectDNS(), packages: packages, fallback: fallback)
            do { try EngineConfiguration.validate(p, binaries: binaries) } catch { try? RuntimeIO.fm.removeItem(at: p.directory); throw error }
            return p
        }.value
        plan = prepared; gate.begin(prepared.id); exitResult = nil; stopping = false
        revision = RuleRevision(token: prepared.initialRevision, route: try Data(contentsOf: prepared.directory.appendingPathComponent("active-route.json")), dns: try Data(contentsOf: prepared.directory.appendingPathComponent("active-dns.json")))
        let command = RuntimeIO.shellQuote(binaries.appendingPathComponent("underpass-helper").path) + " --session " + RuntimeIO.shellQuote(prepared.directory.path)
        let script = "with timeout of 2147483647 seconds\ndo shell script " + RuntimeIO.appleScriptString(command) + " with administrator privileges with prompt " + RuntimeIO.appleScriptString("暗渡需要创建临时 TUN 并管理系统代理。全部关闭后恢复原设置。") + "\nend timeout"
        let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]; p.standardOutput = pipe; p.standardError = pipe
        p.terminationHandler = { [weak self] proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let canceled = String(decoding: data, as: UTF8.self).contains("-128")
            Task { @MainActor in
                guard let self, self.gate.accepts(prepared.id) else { return }
                self.exitResult = (proc.terminationStatus, canceled); self.authorization = nil
                self.eraseCredentials(prepared)
                if !self.busy { self.readTerminalStatus(prepared) }
            }
        }
        authorization = p
        do {
            try p.run()
            for _ in 0..<3000 {
                guard gate.accepts(prepared.id), !stopping else { throw UnderpassError.message("启动已取消。") }
                if let state = status(prepared), state["state"] as? String == "ready" {
                    let client = EngineClient(plan: prepared)
                    try await client.confirm(prepared.initialRevision)
                    try await client.settle(affected: packages)
                    guard gate.accepts(prepared.id), authorization != nil else { throw UnderpassError.message("启动期间助手已退出。") }
                    active = packages; message = "内核与规则已确认；请重开应用或网页后验证播放。"; return
                }
                if let state = status(prepared), state["state"] as? String == "error" { throw UnderpassError.message(state["message"] as? String ?? "助手启动失败。") }
                if let exitResult { throw UnderpassError.message(exitResult.1 ? "已取消管理员授权，网络设置未改变。" : "助手已退出，请查看本地日志。") }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw UnderpassError.message("管理员授权或通道启动超时。")
        } catch {
            let original = error
            try? await stop()
            if authorization == nil { eraseCredentials(prepared) }
            failure = original.localizedDescription; throw original
        }
    }
    func stop() async throws {
        guard let plan, authorization != nil else { active = []; connections = []; return }
        stopping = true; message = "正在关闭共享会话并恢复原系统代理。"
        try RuntimeIO.secureWrite(Data(), to: plan.directory.appendingPathComponent("stop"))
        for _ in 0..<180 {
            let state = status(plan)
            if state?["state"] as? String == "stopped" {
                active = []; connections = []; revision = nil; message = "原系统代理已恢复；所有通道沿用原规则。"
                // Wait for the authorization wrapper to exit before allowing a new session.
                if authorization == nil { gate.end(plan.id); stopping = false; return }
            }
            if authorization == nil {
                active = []; connections = []; stopping = false
                if let state, state["state"] as? String == "error" { failure = state["message"] as? String; throw UnderpassError.message(failure ?? "恢复未确认。") }
                if state?["state"] as? String != "stopped", exitResult?.1 != true { failure = "助手异常结束，系统代理恢复未确认。请使用“恢复残留设置”。"; throw UnderpassError.message(failure!) }
                message = exitResult?.1 == true ? "已取消管理员授权。" : "原系统代理已恢复。"; gate.end(plan.id); return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        failure = "尚未确认助手退出与代理恢复。若授权窗口仍在等待，请取消授权；可稍后使用恢复残留设置。"
        throw UnderpassError.message(failure!)
    }
    private func status(_ p: SessionPlan) -> [String: Any]? { try? RuntimeIO.object(p.directory.appendingPathComponent("status.json")) }
    private func eraseCredentials(_ p: SessionPlan) { for name in ["xray.json", "sing-box.json"] { try? RuntimeIO.fm.removeItem(at: p.directory.appendingPathComponent(name)) } }
    private func readTerminalStatus(_ p: SessionPlan) {
        active = []; connections = []
        let s = status(p)
        if s?["state"] as? String == "error" { failure = s?["message"] as? String ?? "会话异常结束。" }
        else if s?["state"] as? String != "stopped" { failure = "助手意外结束，请检查代理设置或使用恢复残留设置。" }
        message = failure ?? "共享会话已关闭，原系统代理已恢复。"
    }
    private func tick() async {
        guard !monitoring else { return }; monitoring = true; defer { monitoring = false }
        guard let p = plan, gate.accepts(p.id), authorization != nil else { return }
        try? RuntimeIO.fm.setAttributes([.modificationDate: Date()], ofItemAtPath: p.directory.appendingPathComponent("heartbeat").path)
        guard !busy, !stopping else { return }
        if let s = status(p), ["error", "stopped"].contains(s["state"] as? String ?? "") { readTerminalStatus(p); return }
        if !active.isEmpty {
            if (try? Data(contentsOf: RuntimeIO.sourceConfig)).map(RuntimeIO.hash) != p.fingerprint || (try? EngineConfiguration.sourceInfo()).map({ RuntimeIO.portOpen($0.1) }) != true {
                busy = true; defer { busy = false }
                try? await stop(); failure = "v2rayN 节点已改变或退出，通道已停止。请手动重新开启。"; return
            }
            if let c = try? await EngineClient(plan: p).connections(), gate.accepts(p.id), !stopping { connections = c }
        }
    }
    func quit() async { busy = true; try? await stop(); busy = false }
}
