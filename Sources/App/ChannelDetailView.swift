import SwiftUI

struct ChannelDetailView: View {
    @ObservedObject var model: UnderpassModel
    @Binding var tab: ChannelDetailTab
    let remove: (InstalledChannel) -> Void
    var body: some View {
        if let selected = model.selected {
            VStack(alignment: .leading, spacing: 0) {
                header(selected)
                Picker("通道详情", selection: $tab) {
                    ForEach(ChannelDetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 22).padding(.bottom, 16).accessibilityLabel("通道详情")
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch tab {
                        case .overview: overview(selected)
                        case .connections: connections(selected)
                        case .configuration: configuration(selected)
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                }.id(selected.id + ":" + tab.rawValue).accessibilityLabel("\(selected.local.name)\(tab.rawValue)")
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.left").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(model.catalog.channels.isEmpty ? "导入你的第一个通道" : "选择一个通道").font(.title3.weight(.semibold))
                Text("在这里查看状态、连接与配置。").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func header(_ item: InstalledChannel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.local.symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(Color.jade)
                    .frame(width: 44, height: 44).background(Color.jade.opacity(0.10), in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.local.name).font(.title2.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                    Text(item.local.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2).help(item.local.summary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ChannelActionsMenu(model: model, item: item, showConfiguration: { tab = .configuration }, remove: { remove(item) })
            }
            HStack(spacing: 10) {
                if item.local.entry != nil {
                    Button { model.open(item) } label: { Label("打开入口", systemImage: "arrow.up.right.square") }.help("打开\(item.local.name)")
                }
                Button { model.verify(item) } label: {
                    Label(model.testingID == item.id ? "测试中…" : "测试连通性", systemImage: "play.fill")
                }.buttonStyle(.borderedProminent)
                    .disabled(!model.isOn(item.id) || model.testingID != nil || model.busy || item.local.tests.isEmpty)
                Spacer(minLength: 0)
                if model.pending.contains(item.id) { ProgressView().controlSize(.small).accessibilityLabel(model.state(item.id)) }
            }.controlSize(.regular)
        }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
    }
    @ViewBuilder private func overview(_ item: InstalledChannel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("连接验证").font(.headline)
            HStack {
                Label("内核与规则", systemImage: "checkmark.shield")
                Spacer()
                Text(model.isOn(item.id) ? "已确认" : model.state(item.id)).foregroundStyle(model.isOn(item.id) ? Color.jade : Color.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("网页与接口", systemImage: "globe")
                    Spacer()
                    Text(model.testingID == item.id ? "测试中" : model.testResults[item.id] == nil ? "未测试" : "上次测试").foregroundStyle(.secondary)
                }
                Text(model.testResults[item.id] ?? (model.isOn(item.id) ? "通过上方按钮检查 HTTPS 端点是否可达。" : "开启左侧通道后可测试连通性。"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Divider()
            HStack { Label("媒体播放", systemImage: "play.rectangle"); Spacer(); Text("需实际验证").foregroundStyle(.secondary) }
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("当前连接").font(.headline)
            HStack {
                Text("\(model.diagnosticConnections.count) 个命中").monospacedDigit()
                Text("· " + ByteCountFormatter.string(fromByteCount: model.diagnosticConnections.reduce(0) { $0 + $1.bytes }, countStyle: .file)).foregroundStyle(.secondary)
                Spacer()
                Button("查看连接") { tab = .connections }.buttonStyle(.link)
            }
            Text("仅统计当前通道可归属的连接，不代表累计流量。").font(.caption).foregroundStyle(.secondary)
        }
        Label(model.isOn(item.id) ? "首次开启后请重开应用或网页，再验证实际播放。" : "关闭表示停止额外接管，流量将沿用原规则。", systemImage: "info.circle")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private func connections(_ item: InstalledChannel) -> some View {
        let hits = model.diagnosticConnections
        HStack {
            Text("\(hits.count) 个当前连接").font(.headline).monospacedDigit()
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: hits.reduce(0) { $0 + $1.bytes }, countStyle: .file)).foregroundStyle(.secondary)
        }
        if hits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.isOn(item.id) ? "暂未捕获此通道的新连接" : "通道尚未开启").font(.headline)
                Text(model.isOn(item.id) ? "打开服务后在这里查看。加密 DNS、已有连接或缺少进程元数据，可能导致连接无法归属。" : "使用左侧开关开启后，再打开对应服务。").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hits, id: \.id) { c in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(c.host.isEmpty ? (c.process.isEmpty ? "未识别的目标" : c.process) : c.host)
                                .font(.system(.callout, design: .monospaced)).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                            Text(c.process.isEmpty ? "通过当前节点" : "\(c.process) · 当前节点").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(ByteCountFormatter.string(fromByteCount: c.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }.padding(.vertical, 10)
                    if c.id != hits.last?.id { Divider() }
                }
            }
        }
        Text("只展示经选定节点且命中本通道规则的当前连接。重叠规则可能归属多个通道。").font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private func configuration(_ item: InstalledChannel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通道包").font(.headline)
            metadata("版本", "v\(item.upstream.version) · \(item.builtIn ? "预装通道包" : "导入通道包")")
            metadata("稳定 ID", item.id)
            metadata("本地配置", item.local == item.upstream ? "与原始包一致" : "包含本地修改")
            metadata("DNS", item.local.dns == "node" ? "匹配域名经节点 DoH" : "沿用原网络 DNS")
            HStack {
                Button("查看 / 编辑 JSON…") { model.error = nil; model.editing = item }
                Button("导出通道…") { model.export(item) }
            }.controlSize(.regular)
        }
        VStack(alignment: .leading, spacing: 14) {
            Text("匹配范围").font(.headline)
            Text("不同匹配类型按“或”组合，多个开启通道取并集。应用规则覆盖包内所有进程；重叠域名优先使用节点 DNS。").font(.callout).foregroundStyle(.secondary)
            ruleSection("精确域名", values: item.local.match.domains)
            ruleSection("域名及子域名", values: item.local.match.domainSuffixes)
            ruleSection("进程", values: item.local.match.processNames)
            ruleSection("应用路径", values: item.local.match.applicationPaths)
        }
        if !item.local.sources.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("规则来源").font(.headline)
                ForEach(item.local.sources, id: \.self) { value in
                    if let url = URL(string: value) { Link(value, destination: url).font(.callout).lineLimit(2).truncationMode(.middle) }
                }
            }
        }
    }
    private func metadata(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout)
    }
    private func ruleSection(_ title: String, values: [String]) -> some View {
        DisclosureGroup("\(title)（\(values.count)）") {
            if values.isEmpty { Text("未设置").foregroundStyle(.secondary).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
            else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(values, id: \.self) { Text($0).font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
        }.font(.callout)
    }
}
