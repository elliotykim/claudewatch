import Foundation

/// Subscription rate-limit usage read from `~/.claude/claudewatch-usage.json`,
/// written by the Claude Code statusline hook.
struct QuotaState: Equatable {
    var fiveHour: Window?
    var weeklyLimits: [NamedWindow] = []

    var updatedAt: Date?
    var lastError: String?

    static let empty = QuotaState()

    struct Window: Equatable {
        /// 0–100 percentage of the rate-limit budget consumed.
        var usedPercentage: Double
        /// When this window resets (if known).
        var resetsAt: Date?

        /// The rate-limit window has elapsed — the data no longer reflects current usage.
        var isExpired: Bool {
            guard let resetsAt else { return false }
            return resetsAt < Date()
        }
    }

    struct NamedWindow: Equatable {
        var label: String
        var usedPercentage: Double
        var resetsAt: Date?

        var isExpired: Bool {
            guard let resetsAt else { return false }
            return resetsAt < Date()
        }
    }

    /// Decode from the JSON written by statusline-hook.sh.
    ///
    /// Accepts `"weekly"` (array of `{label, used_percentage, resets_at}`) or
    /// the legacy `"seven_day"` single-window format.
    static func from(data: Data) -> QuotaState? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var state = QuotaState.empty

        if let fh = json["five_hour"] as? [String: Any],
           let pct = (fh["used_percentage"] as? NSNumber)?.doubleValue {
            var w = Window(usedPercentage: pct)
            if let epoch = (fh["resets_at"] as? NSNumber)?.doubleValue {
                w.resetsAt = Date(timeIntervalSince1970: epoch)
            }
            state.fiveHour = w
        }

        if let weekly = json["weekly"] as? [[String: Any]] {
            for entry in weekly {
                guard let label = entry["label"] as? String,
                      let pct = (entry["used_percentage"] as? NSNumber)?.doubleValue
                else { continue }
                var nw = NamedWindow(label: label, usedPercentage: pct)
                if let epoch = (entry["resets_at"] as? NSNumber)?.doubleValue {
                    nw.resetsAt = Date(timeIntervalSince1970: epoch)
                }
                state.weeklyLimits.append(nw)
            }
        } else if let sd = json["seven_day"] as? [String: Any],
                  let pct = (sd["used_percentage"] as? NSNumber)?.doubleValue {
            var nw = NamedWindow(label: "All models", usedPercentage: pct)
            if let epoch = (sd["resets_at"] as? NSNumber)?.doubleValue {
                nw.resetsAt = Date(timeIntervalSince1970: epoch)
            }
            state.weeklyLimits.append(nw)
        }

        if let epoch = (json["updated_at"] as? NSNumber)?.doubleValue {
            state.updatedAt = Date(timeIntervalSince1970: epoch)
        }

        return state
    }
}
