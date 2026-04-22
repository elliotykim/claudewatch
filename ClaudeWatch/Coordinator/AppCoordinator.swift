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
    @Published private(set) var uptime: [ComponentUptime] = []

    let preferences = Preferences.shared
    let history = UsageHistoryStore()

    private let quotaClient = QuotaSyncClient()
    private let statusClient = StatusClient()
    private let uptimeClient = UptimeClient()

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

            recordHistory(state: state, observedAt: state.updatedAt ?? Date())

            lastFiveHourResetsAt = state.fiveHour?.resetsAt
            lastFiveHourUsagePercent = state.fiveHour?.usedPercentage
            quota = state
        } else {
            quota.lastError = "No data — is the statusline hook configured in Claude Code?"
        }
    }

    /// Emits session start/update/end events to the usage history store.
    ///
    /// - `start`  — the 5-hour window's `resetsAt` changed (new session), or
    ///   there are no persisted events yet and we've just observed a window.
    /// - `update` — same session, and `usedPercentage` strictly increased
    ///   since the last recorded event.
    /// - `end`    — written immediately before a new session's `start`,
    ///   capturing the outgoing session's last known percent. We can only
    ///   know a session is over once a newer one appears.
    ///
    /// No-op when the same session is observed with unchanged (or decreased)
    /// percentage, which keeps the log compact.
    private func recordHistory(state: QuotaState, observedAt: Date) {
        guard let fh = state.fiveHour else { return }

        let lastEvent = history.events.last

        // A fresh install / first launch with an in-progress session: seed a
        // `start` at the current percent so the session shows up on the graph
        // without a fabricated 0%.
        if lastEvent == nil {
            history.append(UsageHistoryEvent(
                kind: .start,
                at: observedAt,
                percent: fh.usedPercentage,
                sessionResetsAt: fh.resetsAt
            ))
            return
        }

        let sameSession = lastEvent?.sessionResetsAt == fh.resetsAt

        if !sameSession {
            // Close out the previous session with its last known percent.
            // The `.end` is dated one millisecond before `observedAt` so
            // sorting the log preserves the logical order (`.end` before
            // the new `.start`) even at identical wall-clock timestamps.
            if let prev = lastEvent, prev.kind != .end {
                history.append(UsageHistoryEvent(
                    kind: .end,
                    at: observedAt.addingTimeInterval(-0.001),
                    percent: prev.percent,
                    sessionResetsAt: prev.sessionResetsAt
                ))
            }
            history.append(UsageHistoryEvent(
                kind: .start,
                at: observedAt,
                percent: fh.usedPercentage,
                sessionResetsAt: fh.resetsAt
            ))
            return
        }

        // Same session — only record when usage increases, to stay compact.
        if let prev = lastEvent, fh.usedPercentage > prev.percent {
            history.append(UsageHistoryEvent(
                kind: .update,
                at: observedAt,
                percent: fh.usedPercentage,
                sessionResetsAt: fh.resetsAt
            ))
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

        await runUptimeFetch()
    }

    private func runUptimeFetch() async {
        if case .success(let components) = await uptimeClient.fetch() {
            uptime = components
        }
    }
}
