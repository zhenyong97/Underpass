import SwiftUI

// Isolated native host for visual QA. Uses temporary data and never starts a session.
@main struct LayoutPreviewApp: App {
    @StateObject private var model: UnderpassModel
    private let width: CGFloat
    private let height: CGFloat
    init() {
        let count = Bundle.main.object(forInfoDictionaryKey: "PreviewChannelCount") as? Int ?? 2
        width = CGFloat(Bundle.main.object(forInfoDictionaryKey: "PreviewWidth") as? Int ?? 820)
        height = CGFloat(Bundle.main.object(forInfoDictionaryKey: "PreviewHeight") as? Int ?? 580)
        let model = UnderpassModel(previewMode: true)
        if let appearance = Bundle.main.object(forInfoDictionaryKey: "PreviewAppearance") as? String { model.appearance = appearance }
        if let base = model.catalog.channels.first, count > model.catalog.channels.count {
            for number in 3...count {
                var p = base.local
                p.id = "org.underpass.layout-preview-\(number)"
                p.name = number == 3 ? "用于验证长名称截断和选中状态的示例通道" : "示例通道 \(number)"
                p.summary = "仅用于布局验证，不会建立网络会话。"
                model.catalog.channels.append(InstalledChannel(upstream: p, local: p, rawSource: (try? p.encoded()) ?? Data(), builtIn: false))
            }
        }
        if count > 2 {
            model.testResults[model.selectedID] = String(repeating: "布局示例：长测试结果会在详情区域换行，打开和测试按钮保持可见。", count: 8)
        }
        _model = StateObject(wrappedValue: model)
    }
    var body: some Scene {
        Window("暗渡 · 布局预览（隔离数据）", id: "layout-preview") {
            UnderpassView(model: model)
        }.defaultSize(width: width, height: height).windowResizability(.contentMinSize).commands { ChannelSearchCommands() }
    }
}
