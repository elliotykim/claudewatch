import Foundation

/// Persists the 5-hour usage event log to JSON in the app's container-scoped
/// Application Support directory. Writable under sandbox without any file
/// exception in entitlements.
///
/// Events are retained indefinitely — the heatmap displays a bounded window
/// (~26 weeks), but the stat grid's "All" duration covers every event ever
/// recorded. Long-term storage cost is low: a year of real usage is only a
/// few hundred KB of JSON.
@MainActor
final class UsageHistoryStore: ObservableObject {
    @Published private(set) var events: [UsageHistoryEvent] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ClaudeWatch", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("usage-history.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    func append(_ event: UsageHistoryEvent) {
        events.append(event)
        save()
    }

    /// Events occurring on or after `cutoff`, useful for filtering to a
    /// user-selected duration.
    func events(since cutoff: Date) -> [UsageHistoryEvent] {
        events.filter { $0.at >= cutoff }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([UsageHistoryEvent].self, from: data)
        else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
