import Foundation
@main struct EngineClientProbe {
    static func main() async throws {
        let a = CommandLine.arguments
        let plan = SessionPlan(id: UUID(), directory: URL(fileURLWithPath: a[2]), relayPort: 0, mixedPort: 0, apiPort: Int(a[1])!, secret: "offline-test-only", fingerprint: "", protocolName: "TEST", initialRevision: a[4])
        let client = EngineClient(plan: plan)
        if a[3] == "confirm" { try await client.confirm(a[4]) }
        if a[3] == "settle" {
            let data = try Data(contentsOf: URL(fileURLWithPath: a[4]))
            let p = try ChannelPackage.decode(data)
            try await client.settle(affected: [p], flushSystemDNS: false)
        }
        print("PASS: EngineClient \(a[3])")
    }
}
