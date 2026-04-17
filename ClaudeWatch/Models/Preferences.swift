import Foundation
import SwiftUI

enum StatusIconMode: String, CaseIterable {
    case always
    case notOperational
    case off

    var label: String {
        switch self {
        case .always:          return "Always"
        case .notOperational:  return "Only when not operational"
        case .off:             return "Off"
        }
    }
}

enum UsageDisplayStyle: String, CaseIterable {
    case none
    case miniBar
    case ring
    case logoFill
    case dots
    case arc

    var label: String {
        switch self {
        case .none:      return "None"
        case .miniBar:   return "Mini bar"
        case .ring:      return "Ring gauge"
        case .logoFill:  return "Logo fill"
        case .dots:      return "Segmented dots"
        case .arc:       return "Arc gauge"
        }
    }
}

enum SessionRenewNotify: String, CaseIterable {
    case off
    case always
    case whenExhausted

    var label: String {
        switch self {
        case .off: return "Off"
        case .always: return "Always"
        case .whenExhausted: return "When exhausted"
        }
    }
}

/// Shared dynamic color threshold: shifts from a base color through
/// yellow → orange → red as usage increases.
private func dynamicColor(_ pct: Double, base: Color) -> Color {
    if pct >= 90 { return .red }
    if pct >= 70 { return .orange }
    if pct >= 50 { return .yellow }
    return base
}

enum GraphicColor: String, CaseIterable {
    case dynamic
    case dynamicWhite
    case dynamicBlack
    case monochrome
    case matchStatus
    case blue
    case indigo
    case purple
    case teal
    case mint
    case pink

    var label: String {
        switch self {
        case .dynamic:      return "Dynamic (blue at low usage)"
        case .dynamicWhite: return "Dynamic (white at low usage)"
        case .dynamicBlack: return "Dynamic (black at low usage)"
        case .monochrome:   return "Monochrome"
        case .matchStatus:  return "Match status color"
        case .blue:         return "Blue"
        case .indigo:       return "Indigo"
        case .purple:       return "Purple"
        case .teal:         return "Teal"
        case .mint:         return "Mint"
        case .pink:         return "Pink"
        }
    }

    func resolve(usagePercent: Double, severity: Severity) -> Color {
        switch self {
        case .dynamic:      return dynamicColor(usagePercent, base: .blue)
        case .dynamicWhite: return dynamicColor(usagePercent, base: .white)
        case .dynamicBlack: return dynamicColor(usagePercent, base: .black)
        case .monochrome:   return .primary
        case .matchStatus:  return severity.color
        case .blue:    return .blue
        case .indigo:  return .indigo
        case .purple:  return .purple
        case .teal:    return .teal
        case .mint:    return .mint
        case .pink:    return .pink
        }
    }
}

enum BarColor: String, CaseIterable {
    case dynamic
    case matchStatus
    case blue
    case indigo
    case purple
    case teal
    case mint
    case pink

    var label: String {
        switch self {
        case .dynamic:     return "Dynamic"
        case .matchStatus: return "Match status color"
        case .blue:        return "Blue"
        case .indigo:      return "Indigo"
        case .purple:      return "Purple"
        case .teal:        return "Teal"
        case .mint:        return "Mint"
        case .pink:        return "Pink"
        }
    }

    func resolve(usagePercent: Double, severity: Severity) -> Color {
        switch self {
        case .dynamic:     return dynamicColor(usagePercent, base: .blue)
        case .matchStatus: return severity.color
        case .blue:    return .blue
        case .indigo:  return .indigo
        case .purple:  return .purple
        case .teal:    return .teal
        case .mint:    return .mint
        case .pink:    return .pink
        }
    }
}

enum UptimeHistory: String, CaseIterable {
    case off
    case thirtyDays
    case sixtyDays
    case ninetyDays

    var days: Int {
        switch self {
        case .off: return 0
        case .thirtyDays: return 30
        case .sixtyDays: return 60
        case .ninetyDays: return 90
        }
    }

    var label: String {
        switch self {
        case .off: return "Off"
        default: return "\(days) days"
        }
    }
}

/// User preferences backed by `UserDefaults`. Observed by SwiftUI views and the
/// AppCoordinator so changes take effect immediately (timer rescheduling, etc.).
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("quotaSyncIntervalSec")      var quotaSyncIntervalSec: Int = 30
    @AppStorage("statusPollIntervalSec")     var statusPollIntervalSec: Int = 300
    @AppStorage("showUsageInMenuBar")         var showUsageInMenuBar: Bool = true
    @AppStorage("showAllAccountsInMenuBar")   var showAllAccountsInMenuBar: Bool = true
    @AppStorage("statusIconMode")             var statusIconMode: StatusIconMode = .always
    @AppStorage("usageDisplayStyle")         var usageDisplayStyle: UsageDisplayStyle = .none

    // Per-severity status notifications
    @AppStorage("notifyStatusRecovered") var notifyStatusRecovered: Bool = true
    @AppStorage("notifyStatusMinor")     var notifyStatusMinor: Bool = true
    @AppStorage("notifyStatusMajor")     var notifyStatusMajor: Bool = true
    @AppStorage("notifyStatusCritical")  var notifyStatusCritical: Bool = true

    // Session renewal notifications
    @AppStorage("sessionRenewNotify") var sessionRenewNotify: SessionRenewNotify = .off

    // Hotkey: Carbon keyCode + modifier mask (cmd|shift|opt|ctrl bits per Carbon).
    @AppStorage("hotkeyKeyCode")  var hotkeyKeyCode: Int = 8        // 'c' key
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0x0900 // cmd | option

    // Colors
    @AppStorage("graphicColor") var graphicColor: GraphicColor = .dynamic
    @AppStorage("progressBarColor") var progressBarColor: BarColor = .dynamic

    // Uptime history
    // Default must match StatusComponent.claudeCodeID; stored as a raw string
    // because @AppStorage default values must be compile-time constants.
    @AppStorage("uptimeHistory") var uptimeHistory: UptimeHistory = .thirtyDays

    // MARK: - Tracked accounts

    /// Persisted list of Claude accounts whose usage ClaudeWatch tracks.
    /// Backed by `UserDefaults` under `trackedAccounts` as JSON-encoded Data.
    /// On first access with no stored value, a "Default" account pointing at
    /// `~/.claude` is seeded so existing single-account users see no regression.
    var accounts: [TrackedAccount] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "trackedAccounts"),
                  let decoded = try? JSONDecoder().decode([TrackedAccount].self, from: data),
                  !decoded.isEmpty
            else {
                return [TrackedAccount.seedDefault()]
            }
            return decoded
        }
        set {
            objectWillChange.send()
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "trackedAccounts")
            }
        }
    }

    func addAccount(_ account: TrackedAccount) {
        var list = accounts
        list.append(account)
        accounts = list
    }

    func removeAccount(id: UUID) {
        accounts = accounts.filter { $0.id != id }
    }

    func updateAccount(_ account: TrackedAccount) {
        accounts = accounts.map { $0.id == account.id ? account : $0 }
    }
}
