import Foundation
import SwiftUI
import Combine

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

/// User preferences backed by `UserDefaults`. Observed by SwiftUI views and the
/// AppCoordinator so changes take effect immediately (timer rescheduling, etc.).
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("quotaSyncIntervalSec")      var quotaSyncIntervalSec: Int = 30
    @AppStorage("statusPollIntervalSec")     var statusPollIntervalSec: Int = 300
    @AppStorage("showUsageInMenuBar")         var showUsageInMenuBar: Bool = true
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
}
