import Foundation
import SwiftUI
import AppKit

/// Owns the timers and observers that drive the app: subscription usage file
/// poll, status poll, sleep/wake refresh, threshold/status notifications.
///
/// Subscription usage comes from `~/.claude/claudewatch-usage.json`,
/// written by the Claude Code statusline hook.
@MainActor
final class AppCoordinator: ObservableObject {

    @Published private(set) var quota: QuotaState = .empty
    @Published private(set) var status: StatusState = .unknown

    let preferences = Preferences.shared

    private let quotaClient = QuotaSyncClient()
    private let statusClient = StatusClient()

    private var quotaTimer: Timer?
    private var statusTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var started = false

    private var lastStatusSeverity: Severity?
    private var lastFiveHourResetsAt: Date?
    private var lastFiveHourUsagePercent: Double?

    func start() {
        guard !started else { return }
        started = true

        AppNotifications.shared.requestAuthorizationIfNeeded()
        scheduleTimers()
        observeWake()

        runQuotaSync()
        Task { await runStatusPoll() }
    }

    func stop() {
        quotaTimer?.invalidate()
        quotaTimer = nil
        statusTimer?.invalidate()
        statusTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        started = false
    }

    func reschedule() {
        quotaTimer?.invalidate()
        statusTimer?.invalidate()
        scheduleTimers()
    }

    // MARK: - Timers

    private func scheduleTimers() {
        quotaTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(preferences.quotaSyncIntervalSec),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.runQuotaSync() }
        }
        statusTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(preferences.statusPollIntervalSec),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in await self?.runStatusPoll() }
        }
    }

    private func observeWake() {
        let nc = NSWorkspace.shared.notificationCenter
        wakeObserver = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.runQuotaSync()
                await self?.runStatusPoll()
            }
        }
    }

    // MARK: - Work units

    private func runQuotaSync() {
        if let state = quotaClient.read() {
            // Detect 5-hour window renewal
            if let newResetsAt = state.fiveHour?.resetsAt,
               let oldResetsAt = lastFiveHourResetsAt,
               newResetsAt != oldResetsAt {
                AppNotifications.shared.sessionRenewed(
                    previousUsagePercent: lastFiveHourUsagePercent
                )
            }

            lastFiveHourResetsAt = state.fiveHour?.resetsAt
            lastFiveHourUsagePercent = state.fiveHour?.usedPercentage
            quota = state
        } else {
            quota.lastError = "No data — is the statusline hook configured in Claude Code?"
        }
    }

    private func runStatusPoll() async {
        switch await statusClient.fetch() {
        case .success(let new):
            if let prev = lastStatusSeverity, prev != new.severity {
                AppNotifications.shared.statusChange(severity: new.severity, description: new.description)
            }
            lastStatusSeverity = new.severity
            status = new
        case .failure(let error):
            status.lastError = error.localizedDescription
            status.lastCheckedAt = Date()
        }
    }
}
