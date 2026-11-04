import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Color {
    static let jade = Color(nsColor: NSColor(name: "UnderpassAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedRed: 0.30, green: 0.81, blue: 0.64, alpha: 1) : NSColor(calibratedRed: 0.02, green: 0.43, blue: 0.30, alpha: 1)
    })
}
enum ChannelDetailTab: String, CaseIterable {
    case overview = "概览", connections = "连接", configuration = "配置"
}
private struct ChannelSearchActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var channelSearchAction: (() -> Void)? {
        get { self[ChannelSearchActionKey.self] }
        set { self[ChannelSearchActionKey.self] = newValue }
    }
}
struct ChannelSearchCommands: Commands {
    @FocusedValue(\.channelSearchAction) private var search
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("查找通道") { search?() }.keyboardShortcut("f").disabled(search == nil)
        }
    }
}
struct UnderpassView: View {
    @ObservedObject var model: UnderpassModel
    @State private var importing = false
    @State private var dropTarget = false
    @State private var removal: InstalledChannel?
    @State private var query = ""
    @State private var filter: ChannelFilter = .all
    @State private var detailTab: ChannelDetailTab = .overview
    @State private var showingMessage = false
    @FocusState private var searchFocused: Bool
    private var activeIDs: Set<String> { Set(model.runtime.active.map(\.id)) }
    private var visibleChannels: [InstalledChannel] { ChannelBrowser.visible(model.catalog.channels, query: query, filter: filter, activeIDs: activeIDs) }
    private var message: String? { model.error ?? model.runtime.failure ?? model.notice }
    private var isError: Bool { model.error != nil || model.runtime.failure != nil }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 250, idealWidth: 274, maxWidth: 300, maxHeight: .infinity)
                ChannelDetailView(model: model, tab: $detailTab, remove: { removal = $0 })
                    .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
            }
            if let message { notice(message) }
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor)).tint(.jade).accentColor(.jade)
        .preferredColorScheme(model.colorScheme)
        .focusedSceneValue(\.channelSearchAction, { searchFocused = true })
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): model.importFiles(urls); case .failure(let error): model.error = error.localizedDescription }
        }
        .sheet(item: $model.importPreview) { preview in ImportPreviewView(model: model, preview: preview).preferredColorScheme(model.colorScheme) }
        .sheet(item: $model.editing) { item in ChannelConfigurationView(model: model, item: item).preferredColorScheme(model.colorScheme) }
        .alert("移除\(removal?.local.name ?? "通道")？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("取消", role: .cancel) { removal = nil }
            Button("移除通道", role: .destructive) { if let item = removal { model.remove(item.id) }; removal = nil }
        } message: { Text("将撤销这个通道的规则并移除安装副本，其他通道保留。源文件不会删除，移除后可以撤销。") }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe").foregroundStyle(.secondary).accessibilityHidden(true)
            Text("v2rayN").font(.headline)
            Text(model.node).foregroundStyle(.secondary).lineLimit(1).help(model.node)
            Button { model.refreshNode() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("重新检测当前节点").accessibilityLabel("重新检测当前节点")
            Spacer(minLength: 12)
            if model.busy { ProgressView().controlSize(.small).accessibilityLabel("正在应用通道") }
            Label(model.busy ? "应用中" : model.runtime.active.isEmpty ? "待开启" : "内核已就绪", systemImage: model.runtime.active.isEmpty ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(model.runtime.active.isEmpty ? Color.secondary : Color.jade).lineLimit(1)
            Divider().frame(height: 18).padding(.horizontal, 2)
            Button { importing = true } label: { Label("导入", systemImage: "plus") }
                .controlSize(.regular).disabled(model.busy).keyboardShortcut("i", modifiers: [.command, .shift]).help("导入 .channel.json 通道包（⇧⌘I）")
            Menu {
                Button("恢复默认通道…") { model.restoreDefaults() }
                Button("撤销上次移除") { model.undoRemoval() }.disabled(model.catalog.lastRemoval == nil)
                Divider()
                Picker("外观", selection: $model.appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Divider()
                Button("恢复残留设置…") { model.recover() }.disabled(model.previewMode)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.busy)
                .accessibilityLabel("通道管理与外观").help("通道管理与外观")
        }.font(.callout).padding(.horizontal, 16).padding(.vertical, 12)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("我的通道").font(.headline)
                    Spacer()
                    Text("\(model.catalog.channels.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 6) {
                    TextField("搜索名称、简介或 ID", text: $query).textFieldStyle(.roundedBorder)
                        .focused($searchFocused).accessibilityLabel("搜索通道")
                    if !query.isEmpty {
                        Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).accessibilityLabel("清除搜索")
                    }
                }
                Picker("显示通道", selection: $filter) {
                    Text("全部").tag(ChannelFilter.all)
                    Text("已开启 \(model.runtime.active.count)").tag(ChannelFilter.enabled)
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("筛选通道")
            }.padding(14)
            if visibleChannels.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.catalog.channels.isEmpty ? "square.stack.3d.up" : "magnifyingglass").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(model.catalog.channels.isEmpty ? "还没有通道" : filter == .enabled && query.isEmpty ? "暂无已开启通道" : "没有匹配的通道").font(.headline)
                    if model.catalog.channels.isEmpty { Text("导入通道包，或将文件拖到这里。").foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    else { Button("显示全部通道") { query = ""; filter = .all }.buttonStyle(.link) }
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding<String?>(get: { model.selectedID.isEmpty ? nil : model.selectedID }, set: { if let id = $0 { model.selectedID = id } })) {
                    ForEach(visibleChannels) { item in
                        channelRow(item).tag(item.id).listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 8))
                    }
                }.listStyle(.sidebar).accessibilityLabel("通道列表")
            }
            if let selected = model.selected, !visibleChannels.contains(where: { $0.id == selected.id }), !visibleChannels.isEmpty {
                Text("所选通道不在当前筛选结果中").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 8)
            }
            Text(".channel.json 可拖入此处").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
        }
        .overlay {
            if dropTarget {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.arrow.up").font(.largeTitle).accessibilityHidden(true)
                    Text("松开以导入通道包").font(.headline)
                    Text(".channel.json").font(.callout)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.97)).foregroundStyle(Color.jade)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.jade, style: StrokeStyle(lineWidth: 2, dash: [6, 4])).padding(5))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            guard !model.busy else { return false }
            Task {
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                    }
                    if let url { urls.append(url) }
                }
                model.importFiles(urls)
            }; return true
        }
    }
    private func channelRow(_ item: InstalledChannel) -> some View {
        HStack(spacing: 9) {
            Image(systemName: item.local.symbol).font(.system(size: 19, weight: .medium)).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.local.name).font(.body.weight(.medium)).lineLimit(1).help(item.local.name)
                Text(model.state(item.id)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(item.local.name, isOn: Binding(get: { model.isOn(item.id) }, set: { model.toggle(item.id, to: $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                .disabled(model.busy || (!model.nodeReady && !model.isOn(item.id)))
                .accessibilityLabel("\(item.local.name)通道").help("关闭后停止额外接管，恢复原规则")
            ChannelActionsMenu(model: model, item: item, showConfiguration: { model.selectedID = item.id; detailTab = .configuration }, remove: { removal = item })
        }.frame(minHeight: 48).contentShape(Rectangle()).accessibilityElement(children: .contain)
    }
    private func notice(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle").foregroundStyle(isError ? Color.red : Color.secondary).accessibilityHidden(true)
            Text(text).font(.callout).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if model.catalog.lastRemoval != nil { Button("撤销移除") { model.undoRemoval() }.disabled(model.busy) }
            Button("详情") { showingMessage = true }.buttonStyle(.link)
                .popover(isPresented: $showingMessage) { ScrollView { Text(text).textSelection(.enabled).padding(18).frame(maxWidth: .infinity, alignment: .leading) }.frame(width: 420, height: 200) }
            if !isError { Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("关闭提示") }
        }.padding(.horizontal, 16).padding(.vertical, 10)
            .background(isError ? Color.red.opacity(0.06) : Color.primary.opacity(0.035))
    }
    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(model.runtime.active.count) 个已开启 · \(model.catalog.channels.count) 个已安装").monospacedDigit()
            Spacer()
            Text("其他流量沿用原规则").help("全部关闭后恢复原系统代理；关闭单项不保证直连。")
            Button("本地日志") { model.logs() }.buttonStyle(.link)
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
    }
}
struct ChannelActionsMenu: View {
    @ObservedObject var model: UnderpassModel
    let item: InstalledChannel
    let showConfiguration: () -> Void
    let remove: () -> Void
    var body: some View {
        Menu {
            Button("查看配置") { showConfiguration() }
            Button("导出通道…") { model.export(item) }
            if item.local.entry != nil { Button("打开\(item.local.name)") { model.open(item) } }
            Divider()
            Button("上移") { model.move(item.id, by: -1) }.disabled(item.id == model.catalog.channels.first?.id)
            Button("下移") { model.move(item.id, by: 1) }.disabled(item.id == model.catalog.channels.last?.id)
            Divider()
            Button("移除通道…", role: .destructive) { remove() }
        } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.busy)
            .accessibilityLabel("\(item.local.name)更多操作").help("查看配置、导出、排序或移除通道")
    }
}
struct ImportPreviewView: View {
    @ObservedObject var model: UnderpassModel
    let preview: ImportPreview
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("合并导入通道").font(.title2.weight(.semibold))
            Text("仅更新预览中的通道。其他通道、排序与本地修改保留。运行中的规则会在内核确认后生效。").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(preview.changes) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(change.name).font(.headline); Spacer(); Text(change.kind).foregroundStyle(change.kind == "冲突" ? Color.orange : Color.jade) }
                            ForEach(Array(change.details.enumerated()), id: \.offset) { _, detail in Text(detail).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                            if !change.candidates.isEmpty {
                                Picker("同名处理", selection: Binding(get: { preview.targets[change.id] ?? "__choose" }, set: { model.chooseTarget(change.id, target: $0) })) {
                                    Text("请选择…").tag("__choose")
                                    Text("作为新通道添加").tag("__new")
                                    ForEach(change.candidates, id: \.self) { id in Text("合并到 \(id)").tag(id) }
                                }
                            }
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("新通道默认关闭 · 冲突保留本地").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { model.importPreview = nil }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(model.busy ? "正在合并…" : "合并导入") { model.confirmImport() }.keyboardShortcut(.defaultAction).disabled(model.busy || preview.unresolved)
            }
        }.padding(24).frame(width: 600, height: 520).tint(.jade)
    }
}
struct ChannelConfigurationView: View {
    @ObservedObject var model: UnderpassModel
    let item: InstalledChannel
    @State private var text = ""
    @State private var editing = false
    @State private var original = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(item.local.name).font(.title2.weight(.semibold)); Spacer(); Text(item.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            Text("域名、进程、应用之间按“或”匹配；应用匹配覆盖包内全部进程。多个开启通道取并集，重叠域名优先使用节点 DNS。关闭恢复原规则，不保证直连。").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Toggle("编辑本地配置", isOn: $editing).toggleStyle(.checkbox).disabled(original)
                Spacer()
                Toggle("查看包原始版本", isOn: $original).toggleStyle(.checkbox).disabled(editing)
            }
            if original { ScrollView { Text(String(data: item.rawSource, encoding: .utf8) ?? "无法显示").font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }.background(Color(nsColor: .textBackgroundColor)) }
            else { TextEditor(text: $text).font(.system(.body, design: .monospaced)).disabled(!editing).border(Color(nsColor: .separatorColor)).accessibilityLabel("通道 JSON 配置") }
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("导出通道…") { model.export(item) }
                Spacer()
                Button("关闭") { model.editing = nil }.keyboardShortcut(.cancelAction).disabled(model.busy)
                if editing { Button("保存本地修改") { model.saveLocal(item, text: text) }.keyboardShortcut(.defaultAction).disabled(model.busy) }
            }
        }.padding(24).frame(width: 660, height: 580).onAppear { text = String(data: (try? item.local.encoded()) ?? Data(), encoding: .utf8) ?? "" }.tint(.jade)
    }
}
