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

    // MARK: - Testing helpers

    func clear() {
        events.removeAll()
        save()
    }

    /// Replaces all persisted events with a synthetic history so the graph has
    /// something to render without waiting for real sessions.
    ///
    /// Sessions are generated strictly sequentially — a new session can only
    /// start at or after the previous session's `resetsAt`, matching the
    /// real-world constraint that only one 5-hour window is ever active.
    /// Gaps between sessions vary from "immediately after reset" to multiple
    /// days (simulating weekends / time off).
    func seedTestData(days: Int = 365, seed: UInt64 = 0xC1A0DE) {
        var rng = SeededRNG(seed: seed)
        var generated: [UsageHistoryEvent] = []

        let now = Date()
        let sessionLength: TimeInterval = 5 * 3600
        let windowStart = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        // `cursor` is the earliest moment the next session is allowed to start.
        var cursor = windowStart

        while cursor < now {
            // Gap before the next session: mostly short (minutes to hours),
            // occasionally long (a day or two off).
            let gap: TimeInterval = {
                let r = rng.double()
                if r < 0.55 { return rng.double() * 4 * 3600 }          // 0–4h
                if r < 0.90 { return (4 + rng.double() * 20) * 3600 }   // 4–24h
                return (24 + rng.double() * 48) * 3600                  // 1–3 days
            }()

            let sessionStart = cursor.addingTimeInterval(gap)
            if sessionStart >= now { break }

            let resetsAt = sessionStart.addingTimeInterval(sessionLength)

            // Target peak for this session.
            let peak: Double = {
                let r = rng.double()
                if r < 0.55 { return 10 + rng.double() * 35 }   // 10–45%
                if r < 0.90 { return 45 + rng.double() * 35 }   // 45–80%
                return 80 + rng.double() * 18                   // 80–98%
            }()

            var percent = 0.5
            generated.append(UsageHistoryEvent(
                kind: .start,
                at: sessionStart,
                percent: percent,
                sessionResetsAt: resetsAt
            ))

            // Monotonically increasing updates toward the peak, spaced within
            // the 5-hour window and always before `now`.
            let updateCount = 1 + Int(rng.double() * 4)   // 1..4
            for i in 1...updateCount {
                let t = sessionStart.addingTimeInterval(
                    sessionLength * Double(i) / Double(updateCount + 1)
                )
                if t >= now { break }
                let fraction = Double(i) / Double(updateCount + 1)
                percent = min(peak, 0.5 + peak * fraction + rng.double() * 2)
                generated.append(UsageHistoryEvent(
                    kind: .update,
                    at: t,
                    percent: percent,
                    sessionResetsAt: resetsAt
                ))
            }

            // Close the session unless it's the ongoing one overlapping now.
            if resetsAt <= now {
                generated.append(UsageHistoryEvent(
                    kind: .end,
                    at: resetsAt,
                    percent: percent,
                    sessionResetsAt: resetsAt
                ))
            }

            // Next session can only start at or after this one's reset.
            cursor = resetsAt
        }

        events = generated
        save()
    }
}

/// Tiny deterministic RNG so seeded test data reproduces run-to-run.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func double() -> Double {
        Double(next() & 0xFFFFFFFF) / Double(UInt32.max)
    }
}
