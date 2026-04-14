import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for the notification
/// kinds we send. Each method checks the relevant preference before posting.
@MainActor
final class AppNotifications {

    static let shared = AppNotifications()
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    func statusChange(severity: Severity, description: String) {
        let prefs = Preferences.shared
        let allowed: Bool
        switch severity {
        case .operational: allowed = prefs.notifyStatusRecovered
        case .minor:       allowed = prefs.notifyStatusMinor
        case .major:       allowed = prefs.notifyStatusMajor
        case .critical:    allowed = prefs.notifyStatusCritical
        }
        guard allowed else { return }

        post(
            id: "status-\(severity.rawValue)-\(Int(Date().timeIntervalSince1970))",
            title: "Claude Code: \(severity.label)",
            body: description
        )
    }

    func sessionRenewed(previousUsagePercent: Double?) {
        switch Preferences.shared.sessionRenewNotify {
        case .off:
            return
        case .whenExhausted:
            guard let pct = previousUsagePercent, pct >= 90 else { return }
        case .always:
            break
        }

        post(
            id: "session-renew-\(Int(Date().timeIntervalSince1970))",
            title: "Claude Code: 5-hour window reset",
            body: "You're back to full capacity in the rolling 5-hour window."
        )
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(req, withCompletionHandler: nil)
    }
}
