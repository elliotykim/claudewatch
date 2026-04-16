import SwiftUI

struct UsageSection: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    /// True when any displayed window has expired past its reset time.
    private var hasExpiredWindow: Bool {
        if coordinator.quota.fiveHour?.isExpired == true { return true }
        return coordinator.quota.weeklyLimits.contains { $0.isExpired }
    }

    var body: some View {
        let _ = tick
        VStack(alignment: .leading, spacing: 8) {
            Text("Your usage limits").font(.headline)

            if let fh = coordinator.quota.fiveHour {
                usageRow(label: "Current session", window: fh)
            }

            if !coordinator.quota.weeklyLimits.isEmpty {
                Divider()
                Text("Weekly limits").font(.subheadline).bold()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coordinator.quota.weeklyLimits.indices, id: \.self) { i in
                        let limit = coordinator.quota.weeklyLimits[i]
                        usageRow(label: limit.label,
                                 usedPercentage: limit.usedPercentage,
                                 resetsAt: limit.resetsAt,
                                 dimmed: limit.isExpired)
                    }
                }
            }

            if coordinator.quota.fiveHour == nil && coordinator.quota.weeklyLimits.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No usage data yet").font(.subheadline).bold()
                    Text("Configure the statusline hook in Claude Code to see your subscription usage here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let updatedAt = coordinator.quota.updatedAt {
                Text("Updated \(Self.relative(updatedAt))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .help(Self.absoluteFormatter.string(from: updatedAt))
            }

            if hasExpiredWindow {
                Text("Usage will update next time Claude Code is used.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let err = coordinator.quota.lastError {
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
        let tint: Color = dimmed ? .gray : Self.color(for: usedPercentage)
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

    private static func color(for pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        if pct >= 50 { return .yellow }
        return .blue
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
