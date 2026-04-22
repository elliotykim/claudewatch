import Foundation

/// Aggregated metrics derived from a window of `UsageHistoryEvent`s. Computed
/// on demand by `UsageHistorySection` — cheap enough that we don't cache.
struct UsageHistoryStats {
    let sessions: Int
    /// Average of per-session peak percentages.
    let avgPeak: Double
    /// Maximum per-session peak percentage observed.
    let maxPeak: Double
    let activeDays: Int
    let currentStreak: Int
    let longestStreak: Int
    /// Weekday (1 = Sunday … 7 = Saturday, matching Calendar) with the most sessions. `nil` if no sessions.
    let busiestWeekday: Int?
    /// Start-of-day → `DailyBucket` for every day with activity in the window.
    let dailyBuckets: [Date: DailyBucket]

    struct DailyBucket {
        /// Number of sessions that started on this day.
        var sessions: Int
        /// Maximum `usedPercentage` seen that day (0–100).
        var peak: Double
        /// Sum of each session's peak `usedPercentage` for that day. Can
        /// exceed 100% — e.g. three back-to-back sessions peaking at 80%
        /// each sums to 240. Used as the heatmap's intensity metric.
        var totalPercent: Double
    }

    static let empty = UsageHistoryStats(
        sessions: 0, avgPeak: 0, maxPeak: 0,
        activeDays: 0, currentStreak: 0, longestStreak: 0,
        busiestWeekday: nil, dailyBuckets: [:]
    )

    /// Compute stats over `events`, assumed to be sorted ascending by `at` and
    /// already filtered to the duration window the caller cares about.
    static func compute(from events: [UsageHistoryEvent], calendar: Calendar = .current) -> UsageHistoryStats {
        guard !events.isEmpty else { return .empty }

        // Group events by session (sessionResetsAt serves as session id).
        var sessionPeaks: [Date: Double] = [:]
        var sessionStarts: [Date: Date] = [:]
        for e in events {
            let key = e.sessionResetsAt ?? e.at
            sessionPeaks[key] = max(sessionPeaks[key] ?? 0, e.percent)
            if e.kind == .start { sessionStarts[key] = e.at }
        }

        let sessions = sessionPeaks.count
        let peaks = Array(sessionPeaks.values)
        let avgPeak = peaks.isEmpty ? 0 : peaks.reduce(0, +) / Double(peaks.count)
        let maxPeak = peaks.max() ?? 0

        // Daily buckets & active-day set.
        var dailyBuckets: [Date: DailyBucket] = [:]
        for (sessionKey, startedAt) in sessionStarts {
            let day = calendar.startOfDay(for: startedAt)
            let peak = sessionPeaks[sessionKey] ?? 0
            var bucket = dailyBuckets[day] ?? DailyBucket(sessions: 0, peak: 0, totalPercent: 0)
            bucket.sessions += 1
            bucket.peak = max(bucket.peak, peak)
            bucket.totalPercent += peak
            dailyBuckets[day] = bucket
        }

        let activeDaysSorted = dailyBuckets.keys.sorted()
        let activeDays = activeDaysSorted.count

        // Streaks over the sorted set of active days.
        var longestStreak = 0
        var run = 0
        var prev: Date?
        for day in activeDaysSorted {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == day {
                run += 1
            } else {
                run = 1
            }
            longestStreak = max(longestStreak, run)
            prev = day
        }

        // Current streak = run of consecutive active days ending today or yesterday.
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var currentStreak = 0
        var probe = activeDaysSorted.contains(today) ? today
                  : activeDaysSorted.contains(yesterday) ? yesterday
                  : nil
        while let d = probe, activeDaysSorted.contains(d) {
            currentStreak += 1
            probe = calendar.date(byAdding: .day, value: -1, to: d)
        }

        // Busiest weekday (1=Sun … 7=Sat per Calendar).
        var weekdayCounts: [Int: Int] = [:]
        for start in sessionStarts.values {
            let w = calendar.component(.weekday, from: start)
            weekdayCounts[w, default: 0] += 1
        }
        let busiestWeekday = weekdayCounts.max(by: { $0.value < $1.value })?.key

        return UsageHistoryStats(
            sessions: sessions,
            avgPeak: avgPeak,
            maxPeak: maxPeak,
            activeDays: activeDays,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            busiestWeekday: busiestWeekday,
            dailyBuckets: dailyBuckets
        )
    }
}
