import SwiftUI

struct UsageSection: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences

    /// The account this section represents. When nil, the legacy single-account
    /// mode is used (read the first/only tracked account). Showing the account
    /// label in the header is driven by whether more than one account exists.
    let account: TrackedAccount?

    init(coordinator: AppCoordinator, preferences: Preferences, account: TrackedAccount? = nil) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.account = account
    }

    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    private var quota: QuotaState {
        if let account, let state = coordinator.quotaByAccount[account.id] {
            return state
        }
        return coordinator.quotaByAccount.values.first ?? .empty
    }

    private var showLabel: Bool {
        account != nil && preferences.accounts.count > 1
    }

    /// True when any displayed window has expired past its reset time.
    private var hasExpiredWindow: Bool {
        if quota.fiveHour?.isExpired == true { return true }
        return quota.weeklyLimits.contains { $0.isExpired }
    }

    var body: some View {
        let _ = tick
        VStack(alignment: .leading, spacing: 8) {
            if showLabel, let label = account?.label {
                Text(label).font(.headline)
            } else {
                Text("Your usage limits").font(.headline)
            }

            if let fh = quota.fiveHour {
                usageRow(label: "Current session", window: fh)
            }

            if !quota.weeklyLimits.isEmpty {
                Divider()
                Text("Weekly limits").font(.subheadline).bold()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(quota.weeklyLimits.indices, id: \.self) { i in
                        let limit = quota.weeklyLimits[i]
                        usageRow(label: limit.label,
                                 usedPercentage: limit.usedPercentage,
                                 resetsAt: limit.resetsAt,
                                 dimmed: limit.isExpired)
                    }
                }
            }

            if quota.fiveHour == nil && quota.weeklyLimits.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No usage data yet").font(.subheadline).bold()
                    Text("Configure the statusline hook in Claude Code to see your subscription usage here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let updatedAt = quota.updatedAt {
                Text("Updated \(Self.relative(updatedAt))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .help(Self.absoluteFormatter.string(from: updatedAt))
            }

            if hasExpiredWindow {
                Text("Usage will update next time Claude Code is used.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let err = quota.lastError {
                Text(err)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onReceive(timer) { tick = $0 }
    }

    // MARK: - Rows

    @ViewBuilder
    private func usageRow(label: String, window: QuotaState.Window) -> some View {
        usageRow(label: label, usedPercentage: window.usedPercentage, resetsAt: window.resetsAt, dimmed: window.isExpired)
    }

    @ViewBuilder
    private func usageRow(label: String, usedPercentage: Double, resetsAt: Date?, dimmed: Bool = false) -> some View {
        let displayPct = dimmed ? 0.0 : usedPercentage
        let tint: Color = dimmed ? .gray : barColor(for: usedPercentage)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.subheadline)
                    if let resets = resetsAt {
                        let verb = resets < Date() ? "Reset" : "Resets"
                        Text("\(verb) \(Self.relative(resets))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .help(Self.absoluteFormatter.string(from: resets))
                    }
                }
                Spacer()
                Text("\(Int(displayPct))% used")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.primary)
            }
            ProgressView(value: min(displayPct, 100), total: 100)
                .tint(tint)
        }
        .opacity(dimmed ? 0.6 : 1.0)
    }

    // MARK: - Helpers

    private func barColor(for pct: Double) -> Color {
        preferences.progressBarColor.resolve(
            usagePercent: pct,
            severity: coordinator.status.severity
        )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
