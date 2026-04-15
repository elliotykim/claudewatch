import SwiftUI

struct StatusSection: View {
    @ObservedObject var coordinator: AppCoordinator

    // Ticks every 30s so the "Last checked" relative time stays fresh.
    @State private var tick = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let _ = tick   // force redraw on each timer tick
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Claude Code status").font(.headline)
                Spacer()
                Button {
                    if let url = URL(string: "https://status.claude.com") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("View status page")
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.status.severity.color)
                    .frame(width: 10, height: 10)
                Text(coordinator.status.description)
                    .font(.subheadline)
                Spacer()
                if let last = coordinator.status.lastCheckedAt {
                    Text(UsageSection.relative(last))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let err = coordinator.status.lastError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .onReceive(timer) { tick = $0 }
    }
}
