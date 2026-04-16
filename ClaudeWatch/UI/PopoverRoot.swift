import SwiftUI

struct PopoverRoot: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences
    var onSettingsChange: () -> Void

    @State private var showingSettings = false

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
        .frame(width: 320)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in
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
            UsageSection(coordinator: coordinator)
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
