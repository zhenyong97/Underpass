import Foundation

protocol RuleRuntime {
    func confirm(_ token: String) async throws
    func settle(affected: [ChannelPackage], flushSystemDNS: Bool) async throws
}
extension EngineClient: RuleRuntime {}
struct RuleRollbackError: LocalizedError {
    var errorDescription: String? { "规则应用与回退均未确认，已要求关闭共享会话并恢复原系统代理。" }
}
enum RuleTransaction {
    static func apply(_ next: RuleRevision, replacing old: RuleRevision, directory: URL, runtime: any RuleRuntime, affected: [ChannelPackage], flushSystemDNS: Bool = true) async throws {
        do {
            try next.write(to: directory)
            try await runtime.confirm(next.token)
            try await runtime.settle(affected: affected, flushSystemDNS: flushSystemDNS)
        } catch {
            let originalError = error
            do {
                try old.write(to: directory)
                try await runtime.confirm(old.token)
                try await runtime.settle(affected: affected, flushSystemDNS: flushSystemDNS)
            } catch { throw RuleRollbackError() }
            throw originalError
        }
    }
}
struct SessionGate {
    private(set) var id: UUID?
    mutating func begin(_ id: UUID) { self.id = id }
    mutating func end(_ id: UUID) { if self.id == id { self.id = nil } }
    func accepts(_ id: UUID) -> Bool { self.id == id }
}
