import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: UnderpassModel?
    private var pendingURLs: [URL] = []
    func attach(_ model: UnderpassModel) {
        self.model = model
        if !pendingURLs.isEmpty { model.importFiles(pendingURLs); pendingURLs = [] }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.runtime.hasSession || model.busy else { return .terminateNow }
        Task { @MainActor in await model.runtime.quit(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func application(_ sender: NSApplication, open urls: [URL]) { if let model { model.importFiles(urls) } else { pendingURLs.append(contentsOf: urls) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct UnderpassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = UnderpassModel(previewMode: ProcessInfo.processInfo.arguments.contains("--preview"))
    var body: some Scene {
        Window("暗渡 · Underpass", id: "channels") {
            UnderpassView(model: model).onAppear { delegate.attach(model) }
        }.defaultSize(width: 820, height: 580).windowResizability(.contentMinSize)
        .commands {
            ChannelSearchCommands()
            CommandGroup(after: .appInfo) {
                Button("打开 v2rayN") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/v2rayN.app")) }
                Button("恢复默认通道…") { model.restoreDefaults() }.disabled(model.busy)
                Button("恢复残留设置…") { model.recover() }.disabled(model.busy)
                Divider()
                Button("关闭全部通道") { Task { await model.runtime.quit() } }.disabled(model.busy || model.runtime.active.isEmpty)
            }
        }
    }
}
