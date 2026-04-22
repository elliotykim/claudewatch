import SwiftUI

struct SettingsSection: View {
    @ObservedObject var preferences: Preferences
    let history: UsageHistoryStore

    /// Notified when something changes that requires the coordinator to
    /// re-schedule its timers or re-register the hotkey.
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.headline)

            Text("Menu bar").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Show Claude Code status")
                Picker("", selection: $preferences.statusIconMode) {
                    ForEach(StatusIconMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            Toggle("Show 5h usage %", isOn: $preferences.showUsageInMenuBar)
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage graphic")
                Picker("", selection: $preferences.usageDisplayStyle) {
                    ForEach(UsageDisplayStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            Text("Colors").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu bar graphic")
                Picker("", selection: $preferences.graphicColor) {
                    ForEach(GraphicColor.allCases, id: \.self) { color in
                        Text(color.label).tag(color)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage bars")
                Picker("", selection: $preferences.progressBarColor) {
                    ForEach(BarColor.allCases, id: \.self) { color in
                        Text(color.label).tag(color)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            Text("Notifications").font(.subheadline).foregroundStyle(.secondary)
            Toggle("Recovered", isOn: $preferences.notifyStatusRecovered)
            Toggle("Degraded / maintenance", isOn: $preferences.notifyStatusMinor)
            Toggle("Partial outage", isOn: $preferences.notifyStatusMajor)
            Toggle("Major outage", isOn: $preferences.notifyStatusCritical)
            VStack(alignment: .leading, spacing: 4) {
                Text("Session renewal")
                Picker("", selection: $preferences.sessionRenewNotify) {
                    ForEach(SessionRenewNotify.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            Text("Uptime history graph").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $preferences.uptimeHistory) {
                    ForEach(UptimeHistory.allCases, id: \.self) { h in
                        Text(h.label).tag(h)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            Text("Usage history").font(.subheadline).foregroundStyle(.secondary)
            Picker("", selection: $preferences.usageHistoryMode) {
                ForEach(UsageHistoryMode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            #if DEBUG
            HStack(spacing: 8) {
                Button("Fill with sample data") { history.seedTestData() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Clear") { history.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.caption)
            #endif

            Divider()

            Group {
                stepper("Usage polling (s)",
                        value: $preferences.quotaSyncIntervalSec,
                        range: 10...300, step: 10, onCommit: onChange)
                stepper("Claude status polling (s)",
                        value: $preferences.statusPollIntervalSec,
                        range: 300...900, step: 60, onCommit: onChange)
            }

            Divider()

            HStack {
                Text("Toggle popover").font(.caption)
                Spacer()
                HotkeyRecorder(preferences: preferences, onChange: onChange)
            }

            Divider()

            Link("See code on Github",
                 destination: URL(string: "https://github.com/elliotykim/claudewatch")!)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        onCommit: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Stepper(value: value, in: range, step: step, onEditingChanged: { editing in
                if !editing { onCommit?() }
            }) {
                Text("\(value.wrappedValue)")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}
