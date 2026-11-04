import Foundation

enum ChannelFilter: String, CaseIterable {
    case all, enabled
}
enum ChannelBrowser {
    static func visible(_ channels: [InstalledChannel], query: String, filter: ChannelFilter, activeIDs: Set<String>) -> [InstalledChannel] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return channels.filter { item in
            (filter == .all || activeIDs.contains(item.id)) &&
                (query.isEmpty || [item.local.name, item.local.summary, item.id].contains { $0.localizedStandardContains(query) })
        }
    }
}
