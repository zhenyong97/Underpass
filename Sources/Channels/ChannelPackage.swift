import Foundation

struct ChannelMatch: Codable, Equatable {
    var domains: [String] = []
    var domainSuffixes: [String] = []
    var processNames: [String] = []
    var applicationPaths: [String] = []
    var isEmpty: Bool { domains.isEmpty && domainSuffixes.isEmpty && processNames.isEmpty && applicationPaths.isEmpty }
    func contains(host: String, process: String = "", path: String = "") -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domains.contains(host) || domainSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
            || (!process.isEmpty && processNames.contains(process))
            || (!path.isEmpty && applicationPaths.contains { path.hasPrefix($0 + "/Contents/") })
    }
}
struct ChannelEntry: Codable, Equatable { var kind: String; var value: String }
struct ChannelTest: Codable, Equatable { var name: String; var url: String }
struct ChannelPackage: Codable, Equatable, Identifiable {
    var schemaVersion: Int = 1
    var id: String
    var version: String
    var name: String
    var icon: String
    var summary: String
    var match: ChannelMatch
    var dns: String
    var entry: ChannelEntry?
    var tests: [ChannelTest]
    var sources: [String]
    var symbol: String { ["music.note", "play.rectangle", "globe", "network", "cloud", "books.vertical", "gamecontroller", "bubble.left.and.bubble.right"].contains(icon) ? icon : "network" }
    func normalized() -> Self {
        var p = self
        func unique(_ a: [String]) -> [String] { Array(Set(a)).sorted() }
        p.match.domains = unique(match.domains.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        p.match.domainSuffixes = unique(match.domainSuffixes.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        p.match.processNames = unique(match.processNames)
        p.match.applicationPaths = unique(match.applicationPaths)
        p.sources = unique(sources)
        return p
    }
    func validate() throws {
        func require(_ valid: Bool, _ message: String) throws { if !valid { throw UnderpassError.message(message) } }
        try require(schemaVersion == 1, "不支持此通道包的 schemaVersion，仅支持 1。")
        try require(id.range(of: "^[a-z0-9][a-z0-9.-]{2,95}$", options: .regularExpression) != nil, "通道 ID 须为 3–96 位小写字母、数字、点或连字符。")
        try require(Self.versionParts(version) != nil, "包版本须为 major.minor.patch 三段非负整数。")
        try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && summary.count <= 500, "名称为空或文字过长。")
        try require(!name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } && !summary.contains("\u{0}"), "文字含不支持的控制字符。")
        try require(icon.count <= 80 && ["node", "system"].contains(dns), "仅支持 node（经节点 DoH）与 system（原 DNS）策略。")
        try require(!match.isEmpty, "通道至少需要一条匹配规则。")
        let domains = match.domains + match.domainSuffixes
        try require(domains.count + match.processNames.count + match.applicationPaths.count <= 4096, "通道规则超过 4096 条。")
        for domain in domains {
            try require(domain.count <= 253 && domain.range(of: "^(?=.{3,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z][a-z0-9-]{1,62}$", options: .regularExpression) != nil && !domain.hasSuffix(".invalid") && !domain.hasSuffix(".local"), "不支持的域名：\(domain.prefix(100))。请使用小写 ASCII/Punycode 域名，不含通配符、URL 或内网后缀。")
        }
        for process in match.processNames {
            try require(!process.isEmpty && process.count <= 160 && !process.contains("/") && !process.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }, "进程名无效。")
        }
        for path in match.applicationPaths {
            try require(path.hasPrefix("/") && path.hasSuffix(".app") && !path.contains("..") && path.count <= 1024 && !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }, "应用匹配仅支持绝对 .app 路径。")
        }
        func webURL(_ string: String) -> URL? {
            guard string.count <= 4096, let u = URL(string: string), u.scheme == "https", u.host != nil, u.user == nil, u.password == nil else { return nil }; return u
        }
        if let entry {
            try require((entry.kind == "url" && webURL(entry.value) != nil) || (entry.kind == "application" && entry.value.hasPrefix("/Applications/") && entry.value.hasSuffix(".app") && !entry.value.contains("..")), "打开入口仅支持 HTTPS 或 /Applications 下的 .app。")
        }
        try require(tests.count <= 8 && sources.count <= 16, "测试或来源条目过多。")
        for test in tests {
            try require(test.name.count <= 80 && webURL(test.url).map { match.contains(host: $0.host!) } == true, "连通性测试须为匹配通道域名的 HTTPS URL。")
        }
        for source in sources { try require(webURL(source) != nil, "规则来源须为 HTTPS URL。") }
    }
    static func versionParts(_ v: String) -> [Int]? {
        let pieces = v.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.count <= 8 && $0.allSatisfy(\.isNumber) && Int($0) != nil }) else { return nil }
        return pieces.map { Int($0)! }
    }
    static func older(_ a: String, than b: String) -> Bool { (versionParts(a) ?? []).lexicographicallyPrecedes(versionParts(b) ?? []) }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 2_097_152, let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UnderpassError.message("通道包须为不超过 2 MB 的 JSON 对象。") }
        func keys(_ value: [String: Any], _ allowed: Set<String>) throws {
            let extra = Set(value.keys).subtracting(allowed)
            if !extra.isEmpty { throw UnderpassError.message("包包含未支持的字段：\(extra.sorted().joined(separator: ", "))。") }
        }
        try keys(raw, ["schemaVersion", "id", "version", "name", "icon", "summary", "match", "dns", "entry", "tests", "sources"])
        if let m = raw["match"] as? [String: Any] { try keys(m, ["domains", "domainSuffixes", "processNames", "applicationPaths"]) }
        if let e = raw["entry"] as? [String: Any] { try keys(e, ["kind", "value"]) }
        if let tests = raw["tests"] as? [[String: Any]] { for t in tests { try keys(t, ["name", "url"]) } }
        let result = try JSONDecoder().decode(Self.self, from: data).normalized()
        try result.validate(); return result
    }
    func encoded() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return try e.encode(self) }
}
