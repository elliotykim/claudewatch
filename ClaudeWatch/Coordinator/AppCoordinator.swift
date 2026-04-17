import Foundation
import SwiftUI
import AppKit

/// Owns the timers and observers that drive the app: subscription usage file
/// poll, status poll, sleep/wake refresh, threshold/status notifications.
///
/// Subscription usage comes from each tracked account's `claudewatch-usage.json`
/// (written by the Claude Code statusline hook per `CLAUDE_CONFIG_DIR`).
@MainActor
final class AppCoordinator: ObservableObject {

    @Published private(set) var quotaByAccount: [UUID: QuotaState] = [:]
    @Published private(set) var status: StatusState = .unknown
    @Published private(set) var uptime: [ComponentUptime] = []

    let preferences = Preferences.shared

    private let statusClient = StatusClient()
    private let uptimeClient = UptimeClient()

    private var quotaTimer: Timer?
    private var statusTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var started = false

    private var lastStatusSeverity: Severity?
    private var lastFiveHourResetsAt: [UUID: Date] = [:]
    private var lastFiveHourUsagePercent: [UUID: Double] = [:]

    /// Aggregate 5-hour window across accounts: picks the one closest to the
    /// limit (highest non-expired percentage), used by the menu bar graphic.
    var aggregateFiveHour: QuotaState.Window? {
        let active = quotaByAccount.values.compactMap { $0.fiveHour }.filter { !$0.isExpired }
        return active.max(by: { $0.usedPercentage < $1.usedPercentage })
    }

    /// Per-account 5-hour windows in the order they appear in Preferences.
    /// Used by the menu bar when displaying all accounts.
    var fiveHourByAccount: [(account: TrackedAccount, window: QuotaState.Window?)] {
        preferences.accounts.map { ($0, quotaByAccount[$0.id]?.fiveHour) }
    }

    func start() {
        guard !started else { return }
        started = true

        AppNotifications.shared.requestAuthorizationIfNeeded()
        scheduleTimers()
        observeWake()

        runQuotaSync()
        Task { await runStatusPoll() }
        Task { await runUptimeFetch() }
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
        // Also re-read quotas so newly-added/removed accounts are reflected.
        runQuotaSync()
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
        let accounts = preferences.accounts
        var updated: [UUID: QuotaState] = [:]

        for account in accounts {
            if var state = QuotaSyncClient.read(account: account) {
                if let newResetsAt = state.fiveHour?.resetsAt,
                   let oldResetsAt = lastFiveHourResetsAt[account.id],
                   newResetsAt != oldResetsAt {
                    AppNotifications.shared.sessionRenewed(
                        accountLabel: accounts.count > 1 ? account.label : nil,
                        previousUsagePercent: lastFiveHourUsagePercent[account.id]
                    )
                }
                if let resetsAt = state.fiveHour?.resetsAt {
                    lastFiveHourResetsAt[account.id] = resetsAt
                }
                if let pct = state.fiveHour?.usedPercentage {
                    lastFiveHourUsagePercent[account.id] = pct
                }
                updated[account.id] = state
            } else {
                var empty = QuotaState.empty
                empty.lastError = "No data — is the statusline hook configured in Claude Code?"
                updated[account.id] = empty
            }
        }

        // Drop state for accounts that were removed.
        let activeIds = Set(accounts.map(\.id))
        lastFiveHourResetsAt = lastFiveHourResetsAt.filter { activeIds.contains($0.key) }
        lastFiveHourUsagePercent = lastFiveHourUsagePercent.filter { activeIds.contains($0.key) }

        quotaByAccount = updated
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

        await runUptimeFetch()
    }

    private func runUptimeFetch() async {
        if case .success(let components) = await uptimeClient.fetch() {
            uptime = components
        }
    }
}
