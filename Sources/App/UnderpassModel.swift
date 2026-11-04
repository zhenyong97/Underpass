import SwiftUI
import AppKit
import Combine

@MainActor final class UnderpassModel: ObservableObject {
    @Published var catalog = ChannelCatalog()
    @Published var node = "等待 v2rayN"
    @Published var nodeReady = false
    @Published var error: String?
    @Published var notice: String?
    @Published var importPreview: ImportPreview?
    @Published var editing: InstalledChannel?
    @Published var selectedID = ""
    @Published var applying = false
    @Published var pending: Set<String> = []
    @Published var testingID: String?
    @Published var testResults: [String: String] = [:]
    @Published var failedIDs: Set<String> = []
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system" {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
    }
    let runtime: SessionController
    let store: ChannelStore
    let previewMode: Bool
    private var defaults: [IncomingChannel] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Timer?
    private var storageReady = false
    var busy: Bool { applying || runtime.busy }
    var selected: InstalledChannel? { catalog.channels.first { $0.id == selectedID } }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    init(previewMode: Bool = false, directory: URL = ChannelStore.defaultDirectory) {
        self.previewMode = previewMode
        runtime = SessionController(monitor: !previewMode)
        let storeDirectory = previewMode && directory == ChannelStore.defaultDirectory
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Underpass-Preview-\(ProcessInfo.processInfo.processIdentifier)") : directory
        store = ChannelStore(directory: storeDirectory)
        do {
            defaults = try ChannelStore.bundled(at: Bundle.main.resourceURL!.appendingPathComponent("Channels"))
            if previewMode { catalog = try ChannelMerger.preview(defaults, catalog: catalog).proposed }
            else { catalog = try store.load(defaults: defaults, legacyDirectory: RuntimeIO.fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicRelay")) }
            selectedID = catalog.channels.first?.id ?? ""; storageReady = true
            if !previewMode, !UserDefaults.standard.bool(forKey: "legacyNoticeShown"), catalog.migrationNote != nil {
                notice = catalog.migrationNote; UserDefaults.standard.set(true, forKey: "legacyNoticeShown")
            }
        } catch { self.error = "加载通道失败：\(error.localizedDescription)" }
        runtime.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        refreshNode()
        if !previewMode { timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshNode() } } }
    }
    func refreshNode() {
        if let info = try? EngineConfiguration.sourceInfo() {
            nodeReady = RuntimeIO.portOpen(info.1); node = nodeReady ? info.0 : "节点未运行"
        } else { nodeReady = false; node = "未读取到节点" }
    }
    func isOn(_ id: String) -> Bool { runtime.active.contains { $0.id == id } }
    func state(_ id: String) -> String {
        if pending.contains(id) { return isOn(id) ? "应用中…" : "正在开启…" }
        if isOn(id) { return "已开启" }
        if failedIDs.contains(id) { return "开启失败" }
        return "已关闭"
    }
    private func packages(_ state: ChannelCatalog, ids: Set<String>) -> [ChannelPackage] { state.channels.filter { ids.contains($0.id) }.map(\.local).sorted { $0.id < $1.id } }
    func toggle(_ id: String, to enabled: Bool) {
        guard !previewMode, !busy, storageReady else { return }
        var proposed = catalog
        guard let index = proposed.channels.firstIndex(where: { $0.id == id }) else { return }
        proposed.channels[index].enabledPreference = enabled
        var ids = Set(runtime.active.map(\.id)); if enabled { ids.insert(id) } else { ids.remove(id) }
        pending = [id]; failedIDs.remove(id)
        Task { let ok = await commit(proposed, activeIDs: ids); if !ok && !isOn(id) { failedIDs.insert(id) } }
    }
    @discardableResult private func commit(_ proposed: ChannelCatalog, activeIDs: Set<String>? = nil) async -> Bool {
        guard !busy, storageReady else { return false }
        applying = true; error = nil; notice = nil
        let previous = runtime.active
        let ids = activeIDs ?? Set(previous.map(\.id))
        let next = packages(proposed, ids: ids)
        if pending.isEmpty { pending = Set(previous.map(\.id)).symmetricDifference(Set(next.map(\.id))).union(next.filter { !previous.contains($0) }.map(\.id)) }
        defer { applying = false; pending = [] }
        do {
            if next != previous { try await runtime.apply(next) }
            var saving = proposed; saving.revision = UUID()
            do { try store.save(saving) }
            catch {
                do { if runtime.active != previous { try await runtime.apply(previous) } }
                catch { await runtime.quit() }
                throw UnderpassError.message("保存失败，已回退本次操作：\(error.localizedDescription)")
            }
            catalog = saving
            if !catalog.channels.contains(where: { $0.id == selectedID }) { selectedID = catalog.channels.first?.id ?? "" }
            failedIDs = failedIDs.intersection(Set(catalog.channels.map(\.id)))
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func importFiles(_ urls: [URL]) {
        guard !busy, storageReady else { return }
        do {
            guard !urls.isEmpty, urls.count <= 100 else { throw UnderpassError.message("请选择 1–100 个通道包。") }
            let incoming = try urls.map { url -> IncomingChannel in
                guard url.isFileURL, url.lastPathComponent.hasSuffix(".channel.json") else { throw UnderpassError.message("请选择 .channel.json 通道包。") }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 2_097_152 else { throw UnderpassError.message("每个包须为不超过 2 MB 的普通文件。") }
                let raw = try Data(contentsOf: url)
                return IncomingChannel(package: try ChannelPackage.decode(raw), raw: raw)
            }
            error = nil; importPreview = try ChannelMerger.preview(incoming, catalog: catalog)
        } catch { self.error = error.localizedDescription }
    }
    func chooseTarget(_ incomingID: String, target: String) {
        guard let p = importPreview else { return }
        var targets = p.targets; targets[incomingID] = target
        do { importPreview = try ChannelMerger.preview(p.incoming, catalog: catalog, targets: targets) } catch { self.error = error.localizedDescription }
    }
    func confirmImport() {
        guard let p = importPreview, !p.unresolved, p.baseRevision == catalog.revision else { error = "列表已变化，请重新预览导入。"; return }
        Task { if await commit(p.proposed) { importPreview = nil; notice = "通道已增量合并；新增通道保持关闭。" } }
    }
    func restoreDefaults() {
        guard !busy else { return }
        do { error = nil; importPreview = try ChannelMerger.preview(defaults, catalog: catalog) } catch { self.error = error.localizedDescription }
    }
    func remove(_ id: String) {
        var proposed = catalog; proposed.remove(id)
        Task { if await commit(proposed) { notice = "已移除安装副本，源文件保留。可撤销移除。" } }
    }
    func undoRemoval() {
        var proposed = catalog; proposed.undoRemoval()
        Task { if await commit(proposed) { notice = "已恢复通道；保持关闭，请按需开启。" } }
    }
    func move(_ id: String, by offset: Int) {
        guard let i = catalog.channels.firstIndex(where: { $0.id == id }), catalog.channels.indices.contains(i + offset) else { return }
        var proposed = catalog; proposed.channels.swapAt(i, i + offset)
        Task { await commit(proposed) }
    }
    func saveLocal(_ item: InstalledChannel, text: String) {
        do {
            let package = try ChannelPackage.decode(Data(text.utf8))
            guard package.id == item.id, package.version == item.local.version else { throw UnderpassError.message("本地编辑须保留 ID 与包版本；版本更新请使用导入。") }
            var proposed = catalog
            guard let index = proposed.channels.firstIndex(where: { $0.id == item.id }) else { return }
            proposed.channels[index].local = package
            Task { if await commit(proposed) { editing = nil; notice = "已保存本地修改；后续导入会保留冲突字段。" } }
        } catch { self.error = error.localizedDescription }
    }
    func export(_ item: InstalledChannel) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = item.id + ".channel.json"; panel.title = "导出通道"
        if panel.runModal() == .OK, let url = panel.url {
            do { try item.local.encoded().write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
        }
    }
    func open(_ item: InstalledChannel) {
        guard let entry = item.local.entry else { return }
        let url = entry.kind == "application" ? URL(fileURLWithPath: entry.value) : URL(string: entry.value)!
        if !NSWorkspace.shared.open(url) { error = "无法打开入口，请检查应用是否安装或浏览器设置。" }
    }
    func verify(_ item: InstalledChannel) {
        guard isOn(item.id), testingID == nil, let plan = runtime.plan else { return }
        let sessionID = plan.id, package = item.local
        testingID = item.id; testResults[item.id] = "正在通过专用通道测试 HTTPS…"
        Task {
            let result = await Task.detached { () -> String in
                package.tests.map { test in
                    let value = try? RuntimeIO.run(URL(fileURLWithPath: "/usr/bin/curl"), ["--silent", "--output", "/dev/null", "--write-out", "%{http_code}", "--connect-timeout", "6", "--max-time", "12", "--noproxy", "", "--proxy", "http://127.0.0.1:\(plan.mixedPort)", test.url])
                    if let v = value, v.0 == 0, let code = Int(v.1), (200..<400).contains(code) { return "\(test.name)可达（HTTP \(code)）" }
                    if let v = value, v.0 == 0 { return "\(test.name)收到 HTTP \(v.1.prefix(3))，需检查访问限制" }
                    return "\(test.name)请求失败（DNS、TLS 或节点连接），请查看本地日志"
                }.joined(separator: "；") + "。媒体播放仍需实际验证。"
            }.value
            testingID = nil
            guard runtime.plan?.id == sessionID, isOn(item.id), catalog.channels.contains(where: { $0.local == package }) else { testResults[item.id] = "配置或会话已变化，测试结果已作废。"; return }
            testResults[item.id] = result
        }
    }
    var diagnosticConnections: [EngineConnection] {
        guard let p = selected?.local, isOn(p.id) else { return [] }
        return runtime.connections.filter { $0.viaNode && $0.matches(p) }
    }
    func logs() {
        let dir = previewMode ? store.directory : runtime.plan?.directory ?? runtime.sessionsBase
        try? RuntimeIO.fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); NSWorkspace.shared.open(dir)
    }
    func recover() {
        guard !previewMode else { return }
        guard !busy, !runtime.hasSession else { error = "当前助手仍在运行，请先关闭通道并等待。"; return }
        let base = runtime.sessionsBase
        guard let dirs = try? RuntimeIO.fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey]) else { notice = "没有暗渡的残留会话。"; return }
        let candidates = dirs.filter { url in
            guard let s = try? RuntimeIO.object(url.appendingPathComponent("status.json")), s["state"] as? String != "stopped", RuntimeIO.fm.fileExists(atPath: url.appendingPathComponent("original-proxy.json").path) else { return false }
            return true
        }
        guard let dir = candidates.sorted(by: { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }).last else { notice = "没有需要恢复的暗渡会话。"; return }
        applying = true
        Task {
            defer { applying = false }
            let command = RuntimeIO.shellQuote(runtime.binaries.appendingPathComponent("underpass-helper").path) + " --recover " + RuntimeIO.shellQuote(dir.path)
            let script = "do shell script " + RuntimeIO.appleScriptString(command) + " with administrator privileges"
            let result = try? await Task.detached { try RuntimeIO.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script]) }.value
            if result?.0 == 0 { notice = "已按原快照恢复仍由暗渡持有的代理设置。" } else { error = "恢复未完成，请检查授权与本地会话日志。" }
        }
    }
}
