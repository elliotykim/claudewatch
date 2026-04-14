import Foundation

/// Claude Code component snapshot from `https://status.claude.com/api/v2/components.json`.
struct StatusState: Equatable {
    var severity: Severity
    var description: String
    var lastCheckedAt: Date?
    var lastError: String?

    static let unknown = StatusState(
        severity: .operational,
        description: "Status not yet checked",
        lastCheckedAt: nil,
        lastError: nil
    )
}
