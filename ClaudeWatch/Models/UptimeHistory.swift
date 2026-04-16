import Foundation

/// Known components on the Claude status page.
struct StatusComponent: Identifiable {
    let id: String
    let name: String

    /// The Claude Code component ID on status.claude.com.
    static let claudeCodeID = "yyzkbfz2thpt"

    static let all: [StatusComponent] = [
        .init(id: "rwppv331jlwc", name: "claude.ai"),
        .init(id: "0qbwn08sd68x", name: "platform.claude.com"),
        .init(id: "k8w3r06qmzrp", name: "Claude API"),
        .init(id: claudeCodeID, name: "Claude Code"),
        .init(id: "bpp5gb3hpjcl", name: "Claude Cowork"),
        .init(id: "0scnb50nvy53", name: "Claude for Government"),
    ]
}

/// Status of a single day in the uptime history.
struct DayStatus: Identifiable {
    var id: Date { date }
    let date: Date
    let severity: Severity
}

/// Uptime history for a single component.
struct ComponentUptime: Identifiable {
    let id: String
    let name: String
    let currentSeverity: Severity
    let days: [DayStatus]           // oldest first, always 90 days
    let uptimeByDuration: [Int: Double]  // days -> percentage, e.g. [30: 99.5, 60: 99.2, 90: 98.8]
}
