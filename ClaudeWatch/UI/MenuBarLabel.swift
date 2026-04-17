import SwiftUI

/// Compact `NSStatusItem` content: usage % + optional graphic + status logo.
struct MenuBarLabel: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences

    var body: some View {
        HStack(spacing: 5) {
            if showStatusIcon {
                ClaudeLogoShape()
                    .fill(coordinator.status.severity.color)
                    .frame(width: 14, height: 14)
            }
            if preferences.showUsageInMenuBar {
                usagePercentages
            }
            usageGraphic
            if !preferences.showUsageInMenuBar && !showStatusIcon
                && preferences.usageDisplayStyle == .none {
                Text("CW")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }

    // MARK: - Usage text

    /// When multiple accounts are configured and the preference is on, render
    /// one percentage per account separated by `/`. Otherwise show a single
    /// percentage (the aggregate max — same as single-account behavior).
    @ViewBuilder
    private var usagePercentages: some View {
        let entries = coordinator.fiveHourByAccount
        if preferences.showAllAccountsInMenuBar && entries.count > 1 {
            HStack(spacing: 3) {
                ForEach(Array(entries.enumerated()), id: \.element.account.id) { index, entry in
                    if index > 0 {
                        Text("/")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    percentageText(entry.window)
                }
            }
        } else {
            percentageText(coordinator.aggregateFiveHour)
        }
    }

    @ViewBuilder
    private func percentageText(_ window: QuotaState.Window?) -> some View {
        if let w = window {
            let expired = w.isExpired
            let displayPct = expired ? 0.0 : w.usedPercentage
            Text("\(Int(displayPct))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(expired ? Color.secondary : Color.primary)
        } else {
            Text("—")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var showStatusIcon: Bool {
        switch preferences.statusIconMode {
        case .always:          return true
        case .notOperational:  return coordinator.status.severity != .operational
        case .off:             return false
        }
    }

    // MARK: - Usage graphic

    private var pct: Double {
        coordinator.aggregateFiveHour?.usedPercentage ?? 0
    }

    @ViewBuilder
    private var usageGraphic: some View {
        switch preferences.usageDisplayStyle {
        case .none:
            EmptyView()
        case .miniBar:
            miniBar
        case .ring:
            ring
        case .logoFill:
            logoFill
        case .dots:
            dots
        case .arc:
            arc
        }
    }

    // MARK: 1. Mini progress bar

    private var miniBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary.opacity(0.15))
                .frame(width: 30, height: 4)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(graphicColor(pct))
                .frame(width: max(1, 30 * min(pct, 100) / 100), height: 4)
        }
    }

    // MARK: 2. Ring gauge

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(pct, 100) / 100)
                .stroke(graphicColor(pct), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
    }

    // MARK: 3. Logo fill

    private var logoFill: some View {
        ClaudeLogoShape()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 14, height: 14)
            .overlay(
                GeometryReader { geo in
                    let fillHeight = geo.size.height * min(pct, 100) / 100
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ClaudeLogoShape()
                            .fill(graphicColor(pct))
                            .frame(height: geo.size.height)
                            .frame(width: geo.size.width, height: fillHeight, alignment: .bottom)
                            .clipped()
                    }
                }
            )
            .frame(width: 14, height: 14)
    }

    // MARK: 4. Segmented dots

    private var dots: some View {
        let total = 5
        let filled = Int((min(pct, 100) / 100) * Double(total) + 0.5)
        return HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filled ? graphicColor(pct) : Color.primary.opacity(0.15))
                    .frame(width: 4, height: 8)
            }
        }
    }

    // MARK: 5. Arc gauge

    private var arc: some View {
        ZStack {
            ArcShape(startAngle: .degrees(135), endAngle: .degrees(405))
                .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ArcShape(
                startAngle: .degrees(135),
                endAngle: .degrees(135 + 270 * min(pct, 100) / 100)
            )
            .stroke(graphicColor(pct), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 14, height: 14)
    }

    // MARK: - Helpers

    private func graphicColor(_ pct: Double) -> Color {
        preferences.graphicColor.resolve(
            usagePercent: pct,
            severity: coordinator.status.severity
        )
    }
}

// MARK: - Arc Shape

private struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
