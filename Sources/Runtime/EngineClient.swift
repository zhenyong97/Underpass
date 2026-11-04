import Foundation

struct EngineConnection {
    var id: String
    var host: String
    var process: String
    var path: String
    var viaNode: Bool
    var bytes: Int64
    func matches(_ p: ChannelPackage) -> Bool { p.match.contains(host: host, process: process, path: path) }
    static func from(_ item: [String: Any]) -> Self? {
        guard let id = item["id"] as? String else { return nil }
        let m = item["metadata"] as? [String: Any] ?? [:]
        var path = m["processPath"] as? String ?? ""
        // sing-box 1.13 appends the owner in parentheses to processPath.
        if path.hasSuffix(")"), let range = path.range(of: " (", options: .backwards) { path = String(path[..<range.lowerBound]) }
        let process = m["process"] as? String ?? (path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent)
        return Self(id: id, host: (m["host"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? m["destinationIP"] as? String ?? "", process: process, path: path, viaNode: (item["chains"] as? [String] ?? []).contains("selected-node"), bytes: (item["download"] as? Int64 ?? 0) + (item["upload"] as? Int64 ?? 0))
    }
}
struct EngineClient {
    let plan: SessionPlan
    func call(_ path: String, method: String = "GET") async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]; config.timeoutIntervalForRequest = 2; config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(plan.apiPort)" + path)!)
        req.httpMethod = method; req.setValue("Bearer \(plan.secret)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw UnderpassError.message("内核控制接口未确认操作。") }
        return data
    }
    func confirm(_ token: String) async throws {
        // A reserved, network-free DNS canary tests the same live rule-set objects used by routing/DNS.
        for _ in 0..<35 {
            _ = try await call("/cache/dns/flush", method: "POST")
            var confirmed = true
            for kind in ["route", "dns"] {
                do {
                    let data = try await call("/dns/query?name=\(token).\(kind).underpass.invalid&type=A")
                    let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if result?["Status"] as? Int != 0 { confirmed = false }
                } catch { confirmed = false }
            }
            if confirmed { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw UnderpassError.message("内核未确认规则重载，将恢复此前配置。")
    }
    func connections() async throws -> [EngineConnection] {
        let data = try await call("/connections")
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (raw?["connections"] as? [[String: Any]] ?? []).compactMap(EngineConnection.from)
    }
    func settle(affected: [ChannelPackage], flushSystemDNS: Bool = true) async throws {
        _ = try await call("/cache/dns/flush", method: "POST")
        for c in try await connections() where affected.contains(where: { c.matches($0) }) {
            _ = try await call("/connections/" + c.id, method: "DELETE")
        }
        if flushSystemDNS {
            let token = UUID().uuidString
            try RuntimeIO.secureWrite(Data(token.utf8), to: plan.directory.appendingPathComponent("dns-flush"))
            for _ in 0..<40 {
                if (try? String(contentsOf: plan.directory.appendingPathComponent("dns-flushed"), encoding: .utf8)) == token { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw UnderpassError.message("系统 DNS 缓存刷新未获助手确认。")
        }
    }
}
