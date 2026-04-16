import SwiftUI

struct UptimeSection: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences

    var body: some View {
        let days = preferences.uptimeHistory.days
        if days > 0,
           let component = coordinator.uptime.first(where: { $0.id == StatusComponent.claudeCodeID }) {
            let sliced = Array(component.days.suffix(days))

            VStack(alignment: .leading, spacing: 4) {
                uptimeBar(days: sliced)

                HStack {
                    Text("\(days) days ago")
                    Spacer()
                    if let pct = component.uptimeByDuration[days] {
                        Text(String(format: "%.2f %% uptime", pct))
                    }
                    Spacer()
                    Text("Today")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func uptimeBar(days: [DayStatus]) -> some View {
        GeometryReader { geo in
            let count = CGFloat(days.count)
            let barWidth = geo.size.width / count

            HStack(spacing: 0) {
                ForEach(days) { day in
                    Rectangle()
                        .fill(day.severity.color)
                        .frame(width: barWidth)
                }
            }
        }
        .frame(height: 4)
    }
}
