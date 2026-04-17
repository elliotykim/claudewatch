import SwiftUI

struct PopoverRoot: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences
    var onSettingsChange: () -> Void

    @State private var showingSettings = false

    /// One column per account; popover grows horizontally so accounts can be
    /// compared side-by-side. Capped at 3 columns to avoid runaway width.
    private var columnCount: Int { min(max(preferences.accounts.count, 1), 3) }
    private static let columnWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                settingsView
            } else {
                mainView
            }

            Divider()
            bottomBar
        }
        .frame(width: CGFloat(columnCount) * Self.columnWidth)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            showingSettings = false
        }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusSection(coordinator: coordinator)

            if preferences.uptimeHistory != .off && !coordinator.uptime.isEmpty {
                UptimeSection(coordinator: coordinator, preferences: preferences)
            }

            Divider()

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(preferences.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 {
                        Divider().padding(.horizontal, 8)
                    }
                    UsageSection(coordinator: coordinator, preferences: preferences, account: account)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
    }

    private var settingsView: some View {
        ScrollView {
            SettingsSection(
                preferences: preferences,
                onChange: onSettingsChange
            )
            .padding(14)
        }
        .frame(minHeight: 400)
    }

    private var bottomBar: some View {
        HStack {
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: showingSettings ? "chevron.left" : "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help(showingSettings ? "Back" : "Settings")

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
