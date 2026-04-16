import SwiftUI

/// Statuspage component severity, mapped from `component.status`.
enum Severity: String, CaseIterable, Codable, Comparable {
    case operational
    case minor
    case major
    case critical

    /// Map a Statuspage component `status` value to a severity.
    init(componentStatus: String) {
        switch componentStatus.lowercased() {
        case "operational": self = .operational
        case "degraded_performance", "under_maintenance": self = .minor
        case "partial_outage": self = .major
        case "major_outage": self = .critical
        default: self = .operational
        }
    }

    /// Map a Statuspage incident `impact` value to a severity.
    init(incidentImpact: String) {
        switch incidentImpact.lowercased() {
        case "minor": self = .minor
        case "major": self = .major
        case "critical": self = .critical
        default: self = .operational
        }
    }

    private var order: Int {
        switch self {
        case .operational: return 0
        case .minor: return 1
        case .major: return 2
        case .critical: return 3
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.order < rhs.order
    }

    var color: Color {
        switch self {
        case .operational: return Color(red: 0x81/255.0, green: 0xAC/255.0, blue: 0x3B/255.0)
        case .minor:       return Color(red: 0xC6/255.0, green: 0xAC/255.0, blue: 0x3E/255.0)
        case .major:       return Color(red: 0xE6/255.0, green: 0x9C/255.0, blue: 0x40/255.0)
        case .critical:    return Color(red: 0xCD/255.0, green: 0x54/255.0, blue: 0x49/255.0)
        }
    }

    var label: String {
        switch self {
        case .operational: return "All systems operational"
        case .minor: return "Minor incident"
        case .major: return "Major incident"
        case .critical: return "Critical incident"
        }
    }

}
