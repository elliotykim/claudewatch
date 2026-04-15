import SwiftUI

struct SettingsSection: View {
    @ObservedObject var preferences: Preferences

    /// Notified when something changes that requires the coordinator to
    /// re-schedule its timers or re-register the hotkey.
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.headline)

            Text("Menu bar").font(.subheadline).foregroundStyle(.black)
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

            Text("Status notifications").font(.subheadline).foregroundStyle(.black)
            Toggle("Recovered", isOn: $preferences.notifyStatusRecovered)
            Toggle("Degraded / maintenance", isOn: $preferences.notifyStatusMinor)
            Toggle("Partial outage", isOn: $preferences.notifyStatusMajor)
            Toggle("Major outage", isOn: $preferences.notifyStatusCritical)

            Divider()

            Text("Session renewal").font(.subheadline).foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notify on 5h window reset")
                Picker("", selection: $preferences.sessionRenewNotify) {
                    ForEach(SessionRenewNotify.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

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
                .font(.caption).foregroundStyle(.black)
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
