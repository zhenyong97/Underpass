import Foundation

struct InstalledChannel: Codable, Equatable, Identifiable {
    var upstream: ChannelPackage
    var local: ChannelPackage
    var rawSource: Data
    var enabledPreference = false
    var builtIn = false
    var id: String { local.id }
}
struct RemovedChannel: Codable, Equatable { var record: InstalledChannel; var index: Int; var wasTombstoned: Bool }
struct ChannelCatalog: Codable, Equatable {
    var schemaVersion = 1
    var revision = UUID()
    var channels: [InstalledChannel] = []
    var removedDefaults: Set<String> = []
    var lastRemoval: RemovedChannel?
    var migrationNote: String?
    mutating func remove(_ id: String) {
        guard let i = channels.firstIndex(where: { $0.id == id }) else { return }
        let item = channels.remove(at: i)
        lastRemoval = RemovedChannel(record: item, index: i, wasTombstoned: removedDefaults.contains(id))
        if item.builtIn { removedDefaults.insert(id) }
    }
    mutating func undoRemoval() {
        guard let r = lastRemoval, !channels.contains(where: { $0.id == r.record.id }) else { return }
        channels.insert(r.record, at: min(r.index, channels.count))
        if !r.wasTombstoned { removedDefaults.remove(r.record.id) }
        lastRemoval = nil
    }
}
struct IncomingChannel { var package: ChannelPackage; var raw: Data; var builtIn: Bool = false }
struct ImportChange: Identifiable {
    var id: String
    var name: String
    var kind: String
    var details: [String]
    var candidates: [String] = []
}
struct ImportPreview: Identifiable {
    var id = UUID()
    var baseRevision: UUID
    var proposed: ChannelCatalog
    var changes: [ImportChange]
    var unresolved: Bool
    var incoming: [IncomingChannel]
    var targets: [String: String]
}

enum ChannelMerger {
    static func merge(base: ChannelPackage, local: ChannelPackage, new: ChannelPackage) -> (ChannelPackage, [String]) {
        var p = new, notes: [String] = []
        p.id = local.id
        func display<T: Encodable>(_ value: T) -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let text = (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "无法显示"
            return String(text.prefix(280)) + (text.count > 280 ? "…（可在配置中查看完整内容）" : "")
        }
        func scalar<T: Equatable & Encodable>(_ old: T, _ mine: T, _ next: T, _ label: String) -> T {
            if mine != old && next != mine {
                if next != old { notes.append("冲突 · \(label)：旧包 \(display(old))；本地 \(display(mine))；新包 \(display(next))。保留本地修改。") }
                return mine
            }
            if next != old { notes.append("更新 · \(label)：\(display(old)) → \(display(next))") }
            return next
        }
        func array(_ old: [String], _ mine: [String], _ next: [String], _ label: String) -> [String] {
            let removed = Set(old).subtracting(next), added = Set(next).subtracting(old)
            if !removed.isEmpty { notes.append("删除旧\(label) · " + removed.sorted().joined(separator: ", ")) }
            if !added.isEmpty { notes.append("新增\(label) · " + added.sorted().joined(separator: ", ")) }
            let localRemovals = Set(old).subtracting(mine)
            if !localRemovals.intersection(next).isEmpty { notes.append("保留本地删除 · \(label)") }
            return Array(Set(mine).subtracting(removed).union(added)).sorted()
        }
        p.name = scalar(base.name, local.name, new.name, "名称")
        p.icon = scalar(base.icon, local.icon, new.icon, "图标")
        p.summary = scalar(base.summary, local.summary, new.summary, "简介")
        p.dns = scalar(base.dns, local.dns, new.dns, "DNS")
        p.entry = scalar(base.entry, local.entry, new.entry, "打开入口")
        p.tests = scalar(base.tests, local.tests, new.tests, "连通性测试")
        p.sources = array(base.sources, local.sources, new.sources, "来源")
        p.match.domains = array(base.match.domains, local.match.domains, new.match.domains, "精确域名")
        p.match.domainSuffixes = array(base.match.domainSuffixes, local.match.domainSuffixes, new.match.domainSuffixes, "后缀域名")
        p.match.processNames = array(base.match.processNames, local.match.processNames, new.match.processNames, "进程")
        p.match.applicationPaths = array(base.match.applicationPaths, local.match.applicationPaths, new.match.applicationPaths, "应用")
        return (p.normalized(), notes)
    }
    static func preview(_ incoming: [IncomingChannel], catalog: ChannelCatalog, targets: [String: String] = [:]) throws -> ImportPreview {
        guard incoming.count <= 100, Set(incoming.map { $0.package.id }).count == incoming.count else { throw UnderpassError.message("一次最多导入 100 个包，同次导入的 ID 不得重复。") }
        var result = catalog, changes: [ImportChange] = [], unresolved = false
        for item in incoming {
            let next = item.package
            try next.validate()
            let sameNames = result.channels.filter { $0.local.name.caseInsensitiveCompare(next.name) == .orderedSame && $0.id != next.id }
            let target = targets[next.id]
            let exact = result.channels.firstIndex { $0.id == next.id }
            if exact == nil && !sameNames.isEmpty && target == nil {
                unresolved = true
                changes.append(.init(id: next.id, name: next.name, kind: "可能重复", details: ["同名但 ID 不同，请选择作为新通道添加，或明确指定合并目标。"], candidates: sameNames.map(\.id)))
                continue
            }
            let index: Int?
            if let exact { index = exact }
            else if let target, target != "__new" {
                guard let found = result.channels.firstIndex(where: { $0.id == target }) else { throw UnderpassError.message("合并目标已不存在。") }
                index = found
            } else { index = nil }
            if let index {
                let previous = result.channels[index]
                if ChannelPackage.older(next.version, than: previous.upstream.version) {
                    changes.append(.init(id: next.id, name: next.name, kind: "跳过旧版", details: ["\(next.version) 早于已安装的 \(previous.upstream.version)，不会自动降级。"])); continue
                }
                var new = next; new.id = previous.id
                if new == previous.upstream {
                    changes.append(.init(id: next.id, name: next.name, kind: "重复", details: ["包内容相同，保留本地配置、开关与排序。"])); continue
                }
                let (merged, notes) = merge(base: previous.upstream, local: previous.local, new: new)
                try merged.validate()
                var details = ["\(previous.upstream.version) → \(new.version)"] + notes
                if previous.upstream.version == new.version { details.insert("同版本内容有变化，请检查差异。", at: 0) }
                result.channels[index].upstream = new
                result.channels[index].rawSource = item.raw
                result.channels[index].local = merged
                changes.append(.init(id: next.id, name: next.name, kind: notes.contains(where: { $0.hasPrefix("冲突") }) ? "冲突" : "更新", details: details))
            } else {
                result.channels.append(.init(upstream: next, local: next, rawSource: item.raw, builtIn: item.builtIn))
                result.removedDefaults.remove(next.id)
                changes.append(.init(id: next.id, name: next.name, kind: "新增", details: ["v\(next.version) · 默认关闭", "作用范围：\(next.match.domains.count + next.match.domainSuffixes.count) 条域名、\(next.match.processNames.count) 个进程、\(next.match.applicationPaths.count) 个应用", "DNS：\(next.dns == "node" ? "经节点 DoH" : "原网络 DNS")"]))
            }
        }
        for i in changes.indices {
            let next = incoming.first { $0.package.id == changes[i].id }!.package
            if !catalog.channels.contains(where: { $0.id == next.id }) {
                changes[i].candidates = catalog.channels.filter { $0.local.name.caseInsensitiveCompare(next.name) == .orderedSame && $0.id != next.id }.map(\.id)
            }
        }
        return ImportPreview(baseRevision: catalog.revision, proposed: result, changes: changes, unresolved: unresolved, incoming: incoming, targets: targets)
    }
}

final class ChannelStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("channels.json") }
    init(directory: URL) { self.directory = directory }
    static var defaultDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Underpass") }
    static func bundled(at directory: URL) throws -> [IncomingChannel] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix(".channel.json") }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
            let data = try Data(contentsOf: $0)
            return IncomingChannel(package: try ChannelPackage.decode(data), raw: data, builtIn: true)
        }
    }
    func load(defaults: [IncomingChannel], legacyDirectory: URL? = nil) throws -> ChannelCatalog {
        if FileManager.default.fileExists(atPath: file.path) {
            let state = try JSONDecoder().decode(ChannelCatalog.self, from: Data(contentsOf: file))
            try validate(state); return state
        }
        var state = ChannelCatalog()
        if let legacyDirectory, FileManager.default.fileExists(atPath: legacyDirectory.path) {
            let legacyCatalog = legacyDirectory.appendingPathComponent("channels.json")
            if FileManager.default.fileExists(atPath: legacyCatalog.path) {
                state = try JSONDecoder().decode(ChannelCatalog.self, from: Data(contentsOf: legacyCatalog)); try validate(state)
            }
            state.migrationNote = "已保留旧 MusicRelay 数据目录；旧版运行会话不会被接管或复制。启动后需手动开启通道。"
        }
        if state.channels.isEmpty && state.removedDefaults.isEmpty { state = try ChannelMerger.preview(defaults, catalog: state).proposed }
        try save(state); return state
    }
    func validate(_ catalog: ChannelCatalog) throws {
        guard catalog.schemaVersion == 1, catalog.channels.count <= 200, Set(catalog.channels.map(\.id)).count == catalog.channels.count else { throw UnderpassError.message("通道目录格式无效；请从 channels.backup.json 恢复，不会覆盖现有数据。") }
        for item in catalog.channels { try item.upstream.validate(); try item.local.validate(); guard item.id == item.upstream.id else { throw UnderpassError.message("通道 ID 不一致。") } }
    }
    func save(_ catalog: ChannelCatalog) throws {
        try validate(catalog)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: file.path) { try RuntimeIO.secureWrite(Data(contentsOf: file), to: directory.appendingPathComponent("channels.backup.json")) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try RuntimeIO.secureWrite(encoder.encode(catalog), to: file)
    }
}
