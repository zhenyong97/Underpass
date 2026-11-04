import Foundation

final class FakeRuntime: RuleRuntime {
    var confirmations: [String] = []
    var failTokens: Set<String> = []
    var settleFailures = 0
    func confirm(_ token: String) async throws { confirmations.append(token); if failTokens.contains(token) { throw UnderpassError.message("injected reload failure") } }
    func settle(affected: [ChannelPackage], flushSystemDNS: Bool) async throws { if settleFailures > 0 { settleFailures -= 1; throw UnderpassError.message("injected cache failure") } }
}
@main struct CoreTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws { checks += 1; if try !value() { throw UnderpassError.message("FAIL: " + message) } }
    static func rejects(_ message: String, _ action: () throws -> Void) throws { var rejected = false; do { try action() } catch { rejected = true }; try expect(rejected, message) }
    static func main() async throws {
        let project = URL(fileURLWithPath: CommandLine.arguments[1])
        let binaries = project.appendingPathComponent("outputs/暗渡.app/Contents/Helpers")
        let root = project.appendingPathComponent(".build/test-" + UUID().uuidString)
        try RuntimeIO.fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? RuntimeIO.fm.removeItem(at: root) }
        let defaults = try ChannelStore.bundled(at: project.appendingPathComponent("Resources/Channels"))
        try expect(defaults.count == 2, "both defaults load from packages")
        let qq = defaults[0].package, bili = defaults[1].package
        try expect(bili.match.contains(host: "upos-sz-mirror.bilivideo.com"), "video CDN covered")
        try expect(bili.match.contains(host: "i0.hdslb.com"), "images covered")
        try expect(!bili.match.contains(host: "bilibili.com.example.org"), "suffix boundary")
        var invalid = qq; invalid.dns = "arbitrary"; try rejects("unknown DNS rejected") { try invalid.validate() }
        invalid = qq; invalid.match.domainSuffixes = ["com"]; try rejects("TLD rejected") { try invalid.validate() }
        invalid = qq; invalid.entry = .init(kind: "url", value: "javascript:alert(1)"); try rejects("script entry rejected") { try invalid.validate() }
        invalid = qq; invalid.tests = [.init(name: "bad", url: "https://example.com")]; try rejects("unmatched probe rejected") { try invalid.validate() }
        var raw = try JSONSerialization.jsonObject(with: qq.encoded()) as! [String: Any]; raw["script"] = "evil"
        try rejects("unknown executable capability rejected") { _ = try ChannelPackage.decode(JSONSerialization.data(withJSONObject: raw)) }
        let browse = try ChannelMerger.preview(defaults, catalog: ChannelCatalog()).proposed.channels
        try expect(ChannelBrowser.visible(browse, query: "bILI", filter: .all, activeIDs: []).map(\.id) == [bili.id], "channel search case insensitive")
        try expect(ChannelBrowser.visible(browse, query: "com.qq", filter: .all, activeIDs: []).map(\.id) == [qq.id], "channel search stable ID")
        try expect(ChannelBrowser.visible(browse, query: "图片", filter: .all, activeIDs: []).map(\.id) == [bili.id], "channel search summary")
        try expect(ChannelBrowser.visible(browse, query: "  ", filter: .all, activeIDs: []) == browse, "empty search preserves installed order")
        try expect(ChannelBrowser.visible(browse, query: "", filter: .enabled, activeIDs: [qq.id]).map(\.id) == [qq.id], "enabled filter uses actual activity")
        try expect(ChannelBrowser.visible(browse, query: "bili", filter: .enabled, activeIDs: [qq.id]).isEmpty, "query and enabled filter intersect")
        try expect(ChannelBrowser.visible(browse, query: "", filter: .enabled, activeIDs: []).isEmpty, "saved preference does not count as active")
        var catalog = try ChannelMerger.preview(defaults, catalog: ChannelCatalog()).proposed
        try expect(catalog.channels.allSatisfy { !$0.enabledPreference }, "new packages off")
        catalog.channels[0].enabledPreference = true
        catalog.channels[0].local.name = "我的音乐"
        catalog.channels[0].local.match.domainSuffixes.append("local-add.example.com")
        let duplicate = try ChannelMerger.preview([defaults[0]], catalog: catalog)
        try expect(duplicate.changes.first?.kind == "重复" && duplicate.proposed == catalog, "same source preserves local changes")
        var next = qq; next.version = "1.1.0"; next.name = "新版名称"; next.match.domainSuffixes.removeAll { $0 == "y.qq.com" }; next.match.domainSuffixes.append("new.example.com"); next.tests = [.init(name: "new", url: "https://new.example.com/")]
        let incoming = IncomingChannel(package: next, raw: try next.encoded())
        let update = try ChannelMerger.preview([incoming], catalog: catalog)
        try expect(update.proposed.channels.count == 2 && update.proposed.channels[1] == catalog.channels[1], "omitted channel untouched")
        try expect(update.proposed.channels[0].local.name == "我的音乐" && update.proposed.channels[0].enabledPreference, "local conflict and preference retained")
        try expect(update.proposed.channels[0].local.match.domainSuffixes.contains("local-add.example.com") && update.proposed.channels[0].local.match.domainSuffixes.contains("new.example.com"), "local and upstream additions union")
        try expect(!update.proposed.channels[0].local.match.domainSuffixes.contains("y.qq.com") && update.changes[0].details.contains { $0.hasPrefix("删除旧") }, "explicit upstream deletion previewed")
        try expect(update.changes[0].kind == "冲突", "conflict visible")
        try expect(update.changes[0].details.contains { $0.contains("我的音乐") && $0.contains("新版名称") }, "preview shows concrete conflicting values")
        let old = try ChannelMerger.preview([defaults[0]], catalog: update.proposed)
        try expect(old.changes[0].kind == "跳过旧版" && old.proposed == update.proposed, "no automatic downgrade")
        var sameVersion = qq; sameVersion.summary = "同版本修订"
        let same = try ChannelMerger.preview([.init(package: sameVersion, raw: try sameVersion.encoded())], catalog: catalog)
        try expect(same.changes[0].details.contains { $0.contains("同版本") }, "same version difference visible")
        try expect(same.changes[0].details.contains { $0.contains("同版本修订") && $0.contains("→") }, "same version preview shows concrete new text")
        var other = qq; other.id = "org.example.music"
        let item = IncomingChannel(package: other, raw: try other.encoded())
        let nameBase = try ChannelMerger.preview(defaults, catalog: ChannelCatalog()).proposed
        let unresolved = try ChannelMerger.preview([item], catalog: nameBase)
        try expect(unresolved.unresolved && unresolved.proposed == nameBase, "same name does not guess")
        let chosen = try ChannelMerger.preview([item], catalog: nameBase, targets: [other.id: qq.id])
        try expect(!chosen.unresolved && chosen.proposed.channels.count == 2, "explicit target merge")
        let appended = try ChannelMerger.preview([item], catalog: nameBase, targets: [other.id: "__new"])
        try expect(appended.proposed.channels.count == 3, "explicit separate install")
        let store = ChannelStore(directory: root.appendingPathComponent("store"))
        try store.save(catalog)
        var removed = catalog; removed.remove(qq.id); try store.save(removed)
        let reloaded = try store.load(defaults: defaults)
        try expect(reloaded.channels.count == 1 && reloaded.removedDefaults.contains(qq.id), "removed built-in not reinstalled on launch")
        let restored = try ChannelMerger.preview(defaults, catalog: reloaded)
        try expect(restored.proposed.channels.count == 2 && !restored.proposed.channels.last!.enabledPreference, "manual defaults incremental and off")
        removed.undoRemoval()
        try expect(removed.channels == catalog.channels && !removed.removedDefaults.contains(qq.id), "undo preserves order and local data")
        let bytes = try Data(contentsOf: store.file)
        var badCatalog = catalog; badCatalog.channels.append(catalog.channels[0])
        try rejects("invalid store transaction rejected") { try store.save(badCatalog) }
        try expect(try Data(contentsOf: store.file) == bytes, "failed save leaves previous data")
        let legacy = root.appendingPathComponent("legacy"); try RuntimeIO.fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        let migrated = try ChannelStore(directory: root.appendingPathComponent("migrated")).load(defaults: defaults, legacyDirectory: legacy)
        try expect(migrated.migrationNote != nil && migrated.channels.count == 2, "legacy location retained without session takeover")
        var gate = SessionGate(); let one = UUID(), two = UUID(); gate.begin(one); gate.begin(two); gate.end(one)
        try expect(gate.accepts(two) && !gate.accepts(one), "stale callback cannot end new session")
        try expect(try EngineConfiguration.fallback(settings: [:], v2Port: 10808) == "direct", "no original proxy keeps direct fallback")
        try expect(try EngineConfiguration.fallback(settings: ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 10808], v2Port: 10808) == "existing-v2rayn", "partial enabled protocols retain v2rayN fallback")
        try rejects("PAC fails before mutation") { _ = try EngineConfiguration.fallback(settings: ["ProxyAutoConfigEnable": 1], v2Port: 10808) }
        try rejects("another active session not hijacked") { _ = try EngineConfiguration.fallback(settings: ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 30000], v2Port: 10808) }
        let proxy: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 30001, "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 40000, "ExceptionsList": ["intranet"]]
        let original: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 10808, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 10808]
        let restoredProxy = ProxyRestoration.restored(current: proxy, original: original, port: 30001)!
        try expect(restoredProxy["HTTPPort"] as? Int == 10808 && restoredProxy["SOCKSPort"] as? Int == 40000, "restore own keys while preserving later edits")
        try expect(restoredProxy["ExceptionsList"] as? [String] == ["intranet"] && ProxyRestoration.restored(current: proxy, original: original, port: 30002) == nil, "restore leaves unrelated settings")
        var processOnly = qq; processOnly.match = ChannelMatch(processNames: ["Player"]); processOnly.tests = []
        let connection = EngineConnection.from(["id": "test", "metadata": ["host": "", "processPath": "/Applications/Player.app/Contents/MacOS/Player (Admin)"], "chains": ["selected-node"], "download": Int64(5)])!
        try expect(connection.matches(processOnly) && connection.process == "Player", "actual Clash processPath owner suffix handled")
        try expect(!connection.matches(bili) && connection.bytes == 5, "per-channel diagnostics avoid global totals")
        let transactionDir = root.appendingPathComponent("rules"); try RuntimeIO.fm.createDirectory(at: transactionDir, withIntermediateDirectories: true)
        let first = try RuleRevision.make([qq]), second = try RuleRevision.make([bili])
        try first.write(to: transactionDir)
        let fake = FakeRuntime(); fake.failTokens = [second.token]
        do { try await RuleTransaction.apply(second, replacing: first, directory: transactionDir, runtime: fake, affected: [qq,bili], flushSystemDNS: false); throw UnderpassError.message("reload failure not thrown") } catch {}
        try expect(try Data(contentsOf: transactionDir.appendingPathComponent("active-route.json")) == first.route && fake.confirmations == [second.token, first.token], "reload failure rolls back both files and confirms old")
        let cache = FakeRuntime(); cache.settleFailures = 1
        do { try await RuleTransaction.apply(second, replacing: first, directory: transactionDir, runtime: cache, affected: [qq,bili], flushSystemDNS: false) } catch {}
        try expect(cache.confirmations == [second.token, first.token], "cache failure rolls back")
        let bothFail = FakeRuntime(); bothFail.failTokens = [first.token, second.token]
        var rollbackFailure = false
        do { try await RuleTransaction.apply(second, replacing: first, directory: transactionDir, runtime: bothFail, affected: [], flushSystemDNS: false) } catch is RuleRollbackError { rollbackFailure = true }
        try expect(rollbackFailure, "rollback failure requires whole-session stop")
        let sample: [String: Any] = ["inbounds": [["protocol": "mixed", "listen": "127.0.0.1", "port": 10808]], "outbounds": [["tag": "proxy", "protocol": "vless", "settings": ["vnext": [["address": "127.0.0.1", "port": 20443, "users": [["id": "00000000-0000-4000-8000-000000000001", "encryption": "none"]]]]]], ["tag": "direct", "protocol": "freedom"]]]
        let source = root.appendingPathComponent("source.json"); try RuntimeIO.jsonWrite(sample, to: source); let before = try Data(contentsOf: source)
        let plan = try EngineConfiguration.makePlan(source: source, base: root, relayPort: 30101, mixedPort: 30102, apiPort: 30103, dns: "10.0.0.1", packages: [qq,bili])
        try EngineConfiguration.validate(plan, binaries: binaries)
        try expect(try Data(contentsOf: source) == before, "source unchanged")
        let xray = try RuntimeIO.object(plan.directory.appendingPathComponent("xray.json"))
        try expect(((xray["routing"] as! [String: Any])["rules"] as! [[String: Any]])[0]["outboundTag"] as? String == "proxy", "all managed traffic forced to node")
        try expect((((xray["inbounds"] as! [[String: Any]])[0]["settings"] as! [String: Any])["auth"] as? String) == "password", "authenticated dedicated ingress")
        let perm = try RuntimeIO.fm.attributesOfItem(atPath: plan.directory.appendingPathComponent("xray.json").path)[.posixPermissions] as! NSNumber
        try expect(perm.intValue == 0o600, "secret permissions")
        if let i = CommandLine.arguments.firstIndex(of: "--emit-fixture"), i + 1 < CommandLine.arguments.count {
            let dest = URL(fileURLWithPath: CommandLine.arguments[i+1]); try RuntimeIO.fm.createDirectory(at: dest, withIntermediateDirectories: true)
            var config = try RuntimeIO.object(plan.directory.appendingPathComponent("sing-box.json"))
            var route = config["route"] as! [String: Any]
            route["rule_set"] = [["type":"local","tag":"active-route","format":"source","path":dest.appendingPathComponent("active-route.json").path],["type":"local","tag":"active-dns","format":"source","path":dest.appendingPathComponent("active-dns.json").path]]
            config["route"] = route; try RuntimeIO.jsonWrite(config, to: dest.appendingPathComponent("config.json"))
            var dynamic = qq; dynamic.id = "org.example.dynamic"; dynamic.name = "Dynamic"; dynamic.match = ChannelMatch(domains: ["third.example.com"]); dynamic.entry = nil; dynamic.tests = []
            for (label, packs) in [("00", []), ("10", [qq]), ("11", [qq,bili]), ("01", [bili]), ("dynamic", [bili,dynamic])] {
                let d = dest.appendingPathComponent(label); try RuntimeIO.fm.createDirectory(at: d, withIntermediateDirectories: true)
                let r = try RuleRevision.make(packs); try r.write(to: d); try Data(r.token.utf8).write(to: d.appendingPathComponent("token"))
            }
            try RuleRevision.make([qq,bili]).write(to: dest)
        }
        if CommandLine.arguments.contains("--real-config") {
            let original = try Data(contentsOf: RuntimeIO.sourceConfig)
            let real = try EngineConfiguration.makePlan(base: root, relayPort: 30201, mixedPort: 30202, apiPort: 30203, dns: RuntimeIO.detectDNS(), packages: [qq,bili])
            try EngineConfiguration.validate(real, binaries: binaries)
            try expect(try Data(contentsOf: RuntimeIO.sourceConfig) == original, "real v2rayN unchanged")
            print("PASS: real node read-only snapshot validates in both bundled cores; credentials removed with test directory")
        }
        print("PASS: \(checks) behavior checks (packages, merge, conflicts, deletion, restore, storage, recovery ownership, stale callbacks, rollback, core config)")
    }
}
