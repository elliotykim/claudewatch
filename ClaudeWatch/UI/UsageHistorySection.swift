import SwiftUI

/// Historical 5-hour usage overview: heatmap + optional stat grid.
///
/// - The heatmap is fixed at 26 weeks × 7 weekdays (182 days). It renders
///   independently of any UI filter so long-term usage shape is always
///   visible. `UsageHistoryStore` retains events indefinitely; only what
///   fits in the grid is loaded for intensity math.
/// - The stat grid and footer caption are filtered by
///   `preferences.usageHistoryDuration` (7d / 30d / All). "All" has no
///   cutoff and covers every retained event. The segmented duration picker
///   is only shown when the stat grid is visible, because it doesn't
///   affect the chart.
/// - Both the stat grid and the whole section are gated on
///   `preferences.usageHistoryMode` (`.off` / `.chart` / `.chartAndStats`).
///   The parent only renders this view when `mode != .off`.
struct UsageHistorySection: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences
    /// Observed directly so view rebuilds on every `events` append — otherwise
    /// `coordinator`'s ObservedObject only propagates coordinator's own
    /// `@Published` properties, not nested stores.
    @ObservedObject var history: UsageHistoryStore

    /// The heatmap cell the cursor is currently over, if any. Updated with
    /// near-zero latency via `.onHover` — replaces the system `.help()`
    /// tooltip which has a ~1.5s OS-level delay.
    @State private var hoveredDay: Date?

    private static let heatmapColumns = 26
    private static let heatmapRows = 7
    private static let heatmapSpacing: CGFloat = 2
    /// Width we expect the heatmap to render at: popover is 320pt, with
    /// 14pt horizontal padding on each side in `PopoverRoot.mainView`.
    /// Used to pre-compute the outer height so the `GeometryReader` has a
    /// bounded vertical space to occupy.
    private static let heatmapAssumedWidth: CGFloat = 292

    /// Exact cell size required to fill `heatmapAssumedWidth` with 26 cells
    /// and 25 spacings. Roughly 9.31pt — fractional sizes render fine.
    private static var heatmapCellSize: CGFloat {
        let cols = CGFloat(heatmapColumns)
        return (heatmapAssumedWidth - heatmapSpacing * (cols - 1)) / cols
    }

    /// Height of the heatmap at `heatmapCellSize`.
    private static var heatmapHeight: CGFloat {
        let rows = CGFloat(heatmapRows)
        return rows * heatmapCellSize + (rows - 1) * heatmapSpacing
    }

    private var showStats: Bool {
        preferences.usageHistoryMode == .chartAndStats
    }

    var body: some View {
        // Compute each stats aggregate at most once per body evaluation and
        // thread the results down through helpers. Accessing the same value
        // via a computed property would re-run `UsageHistoryStats.compute`
        // for every call site (6+ per render for the stat grid alone).
        let hEvents = heatmapEvents()
        let heatmapStats = UsageHistoryStats.compute(from: hEvents)
        // `stats` is only needed when the grid is visible or the caption
        // falls through to the window summary; skip the filter+compute
        // otherwise and let captionText's guard short-circuit on zero.
        let stats = showStats
            ? UsageHistoryStats.compute(from: statsEvents())
            : .empty

        return VStack(alignment: .leading, spacing: 10) {
            header

            if hEvents.isEmpty {
                Text("No usage recorded yet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                overview(heatmapStats: heatmapStats, stats: stats)
            }
        }
    }

    // MARK: - Event & stats windows

    /// Events in the window the heatmap displays — 26 weeks = 182 days.
    /// The store retains every event; this just crops to what the grid can
    /// show so intensity math doesn't scan ancient history.
    private func heatmapEvents() -> [UsageHistoryEvent] {
        let days = Self.heatmapColumns * Self.heatmapRows
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return history.events(since: cutoff)
    }

    /// Events in the user-selected duration window (7d / 30d / All) — drives
    /// the stat grid and footer summary. `.all` has no cutoff and returns
    /// every retained event.
    private func statsEvents() -> [UsageHistoryEvent] {
        let cutoff = preferences.usageHistoryDuration.cutoff(from: Date())
        return history.events(since: cutoff)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Usage history").font(.headline)
            Spacer()
            // Duration only affects stats, so hide the picker entirely when
            // the stat grid isn't visible.
            if showStats {
                durationPicker
            }
        }
    }

    private var durationPicker: some View {
        Picker("", selection: $preferences.usageHistoryDuration) {
            ForEach(UsageHistoryDuration.allCases, id: \.self) { d in
                Text(d.shortLabel).tag(d)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
    }

    // MARK: - Overview

    private func overview(heatmapStats: UsageHistoryStats, stats: UsageHistoryStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showStats {
                statGrid(stats: stats)
            }
            heatmap(heatmapStats: heatmapStats)
            footerCaption(heatmapStats: heatmapStats, stats: stats)
        }
    }

    private func statGrid(stats: UsageHistoryStats) -> some View {
        // 3 cols × 2 rows. LazyVGrid fills row-by-row, so column pairs are
        // formed by the items at indices (i, i+3).
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            statCard(label: "Sessions",       value: "\(stats.sessions)")
            statCard(label: "Avg peak",       value: "\(Int(stats.avgPeak.rounded()))%")
            statCard(label: "Current streak", value: "\(stats.currentStreak)d")
            statCard(label: "Active days",    value: "\(stats.activeDays)")
            statCard(label: "Max peak",       value: "\(Int(stats.maxPeak.rounded()))%")
            statCard(label: "Longest streak", value: "\(stats.longestStreak)d")
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .default))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    // MARK: - Heatmap

    /// Calendar-aligned grid: 26 columns × 7 rows (182 cells / 26 weeks).
    /// Columns are weeks (oldest → newest); rows are weekdays aligned so the
    /// top row is the locale's `firstWeekday`. `today` lands in the last
    /// column at its weekday row; cells to the right of `today` stay clear.
    ///
    /// Cell size is computed from the container's measured width so the grid
    /// fills the full content column and aligns with the stat cards'
    /// left/right edges. Intensity is driven by summed session percentages
    /// for that day, bucketed into 4 levels + empty.
    ///
    /// Independent of `preferences.usageHistoryDuration` — always shows the
    /// full 26-week window so long-term shape stays visible as the user
    /// switches stat durations.
    private func heatmap(heatmapStats: UsageHistoryStats) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let firstWeekday = calendar.firstWeekday
        // Row index (0..6) today will occupy in the *last* column.
        let rowOfToday = ((todayWeekday - firstWeekday) + 7) % 7
        let todayOffset = (Self.heatmapColumns - 1) * Self.heatmapRows + rowOfToday
        let gridStart = calendar.date(byAdding: .day, value: -todayOffset, to: today) ?? today

        // Intensity scales against the busiest day in the visible window,
        // measured by summed session percentages (not session count).
        let maxTotal = max(1, heatmapStats.dailyBuckets.values.map(\.totalPercent).max() ?? 1)

        // GeometryReader reads the actual available width — if the popover
        // width ever changes, cells resize to fill it precisely. The outer
        // `.frame(height:)` is required because GeometryReader has no
        // intrinsic size; without it the view collapses to a tiny default.
        return GeometryReader { geo in
            let cols = CGFloat(Self.heatmapColumns)
            let s = Self.heatmapSpacing
            let cellSize = max(1, (geo.size.width - s * (cols - 1)) / cols)

            HStack(alignment: .top, spacing: s) {
                ForEach(0..<Self.heatmapColumns, id: \.self) { col in
                    VStack(spacing: s) {
                        ForEach(0..<Self.heatmapRows, id: \.self) { row in
                            let offset = col * Self.heatmapRows + row
                            let day = calendar.date(byAdding: .day, value: offset, to: gridStart) ?? gridStart
                            cell(for: day, today: today, maxTotal: maxTotal,
                                 cellSize: cellSize, heatmapStats: heatmapStats)
                        }
                    }
                }
            }
        }
        .frame(height: Self.heatmapHeight)
    }

    @ViewBuilder
    private func cell(for day: Date, today: Date, maxTotal: Double,
                      cellSize: CGFloat, heatmapStats: UsageHistoryStats) -> some View {
        let isFuture = day > today
        let bucket = heatmapStats.dailyBuckets[day]
        let level: Int = {
            guard let b = bucket, b.totalPercent > 0 else { return 0 }
            let frac = b.totalPercent / maxTotal
            if frac < 0.34 { return 1 }
            if frac < 0.67 { return 2 }
            if frac < 1.0 { return 3 }
            return 4
        }()

        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(isFuture ? Color.clear : cellColor(level: level))
            .frame(width: cellSize, height: cellSize)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard !isFuture else { return }
                hoveredDay = hovering ? day : (hoveredDay == day ? nil : hoveredDay)
            }
    }

    /// Heatmap cell fill color.
    ///
    /// Levels 1–4 use the user's `progressBarColor` so the chart matches the
    /// usage progress bars. Level 0 (empty) stays on a neutral light-gray
    /// that adapts to light/dark mode.
    private func cellColor(level: Int) -> Color {
        let tint = progressBarTint
        switch level {
        case 0: return Self.emptyCellColor
        case 1: return tint.opacity(0.40)
        case 2: return tint.opacity(0.75)
        case 3: return tint.opacity(1.00)
        default: return tint
        }
    }

    /// The heatmap tint — resolved from the user's `progressBarColor`
    /// preference so the historical chart matches the 5-hour progress bar.
    /// For the `.dynamic` option, the base color is used (at 0% usage) to
    /// keep the heatmap's palette stable instead of shifting with current
    /// usage.
    private var progressBarTint: Color {
        preferences.progressBarColor.resolve(
            usagePercent: 0,
            severity: coordinator.status.severity
        )
    }

    // MARK: - Footer

    /// When hovering a cell, show that day's summary. Otherwise, the
    /// overall-window summary. Reserves a fixed height so rows don't reflow
    /// as the cursor moves.
    @ViewBuilder
    private func footerCaption(heatmapStats: UsageHistoryStats, stats: UsageHistoryStats) -> some View {
        Text(captionText(heatmapStats: heatmapStats, stats: stats))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func captionText(heatmapStats: UsageHistoryStats, stats: UsageHistoryStats) -> String {
        if let hoveredDay {
            // Use the full heatmap stats — hovering an old cell should show
            // its real activity, not "no activity" just because the current
            // stats duration excludes it.
            return cellHelp(day: hoveredDay, bucket: heatmapStats.dailyBuckets[hoveredDay])
        }
        // `stats` is `.empty` when `showStats` is false (see `body`), so
        // the guard on `sessions > 0` also covers the no-panel case.
        guard showStats, stats.sessions > 0 else { return "" }
        let base = "\(stats.sessions) sessions across \(stats.activeDays) active days"
        if let w = stats.busiestWeekday, let name = Self.weekdayName(w) {
            return "\(base). Busiest day: \(name)."
        }
        return "\(base)."
    }

    private func cellHelp(day: Date, bucket: UsageHistoryStats.DailyBucket?) -> String {
        let dayStr = Self.dayFormatter.string(from: day)
        guard let b = bucket else { return "\(dayStr) — no activity" }
        let total = Int(b.totalPercent.rounded())
        return "\(dayStr) — \(b.sessions) session\(b.sessions == 1 ? "" : "s"), total \(total)%"
    }

    // MARK: - Helpers

    /// Empty-cell color — dynamic so it stays visible in both modes.
    /// Light: near-black at low alpha; Dark: near-white at higher alpha.
    private static let emptyCellColor = Color(nsColor: NSColor(name: "heatmapEmpty") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil {
            return NSColor(calibratedWhite: 1.0, alpha: 0.18)
        }
        return NSColor(calibratedWhite: 0.0, alpha: 0.08)
    })

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static func weekdayName(_ weekday: Int) -> String? {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return nil }
        return symbols[weekday - 1]
    }
}
