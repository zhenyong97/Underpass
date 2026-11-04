import Foundation
import CryptoKit
import Darwin

enum UnderpassError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum RuntimeIO {
    static let fm = FileManager.default
    static var v2Directory: URL { fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/v2rayN") }
    static var sourceConfig: URL { v2Directory.appendingPathComponent("binConfigs/config.json") }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func jsonWrite(_ object: Any, to url: URL) throws {
        try secureWrite(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), to: url)
    }
    static func object(_ url: URL) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw UnderpassError.message("配置文件格式不正确。请在 v2rayN 中重新启动当前节点。")
        }
        return value
    }
    static func availablePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnderpassError.message("无法分配本地端口。") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0 else { throw UnderpassError.message("无法分配本地端口。") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        return Int(UInt16(bigEndian: address.sin_port))
    }
    static func portOpen(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
    }
    static func run(_ binary: URL, _ arguments: [String], environment: [String: String]? = nil) throws -> (Int32, String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = binary; p.arguments = arguments
        p.standardOutput = pipe; p.standardError = pipe
        if let environment { p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new } }
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    static func detectDNS() -> String {
        if let result = try? run(URL(fileURLWithPath: "/usr/sbin/scutil"), ["--dns"]), result.0 == 0 {
            for line in result.1.components(separatedBy: .newlines) where line.contains("nameserver[") {
                let candidate = line.components(separatedBy: " : ").last?.trimmingCharacters(in: .whitespaces) ?? ""
                var address = in_addr()
                if inet_pton(AF_INET, candidate, &address) == 1 && !candidate.hasPrefix("127.") { return candidate }
            }
        }
        if let text = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) where line.hasPrefix("nameserver ") {
                let candidate = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                var address = in_addr()
                if inet_pton(AF_INET, candidate, &address) == 1 && !candidate.hasPrefix("127.") { return candidate }
            }
        }
        return "119.29.29.29"
    }
    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
