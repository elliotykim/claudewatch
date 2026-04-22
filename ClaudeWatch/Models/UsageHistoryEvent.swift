import Foundation

/// A recorded point in the 5-hour usage timeline. Only three kinds of events
/// are persisted to keep the log compact:
///
/// - `start` — first observation of a new 5-hour window.
/// - `update` — subsequent observations where `used_percentage` increased.
/// - `end` — last known percentage for a window, recorded the moment a newer
///   window is observed.
///
/// `sessionResetsAt` is the `resets_at` of the 5-hour window and serves as the
/// session identifier — all events sharing that value belong to one session.
struct UsageHistoryEvent: Codable, Equatable {
    enum Kind: String, Codable { case start, update, end }

    let kind: Kind
    let at: Date
    let percent: Double
    let sessionResetsAt: Date?
}
