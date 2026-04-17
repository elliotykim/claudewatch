import SwiftUI
import AppKit

/// Settings pane for managing tracked Claude accounts. Each account maps to
/// its own `CLAUDE_CONFIG_DIR` on disk; usage is read via a security-scoped
/// bookmark created when the user picks the directory.
struct AccountsSection: View {
    @ObservedObject var preferences: Preferences
    var onChange: () -> Void

    @State private var accounts: [TrackedAccount] = []
    @State private var showingAddError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude accounts").font(.subheadline).foregroundStyle(.secondary)

            Text("Track multiple Claude accounts by running Claude Code with different CLAUDE_CONFIG_DIR values. See the README for setup.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(accounts) { account in
                HStack(spacing: 8) {
                    TextField("Label", text: labelBinding(for: account))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                    Text(shortPath(account.configDir))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(action: { remove(account) }) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Remove account")
                    .disabled(accounts.count <= 1)
                }
            }

            HStack {
                Button("Add account…") { addAccount() }
                    .controlSize(.small)
                Spacer()
            }

            if let err = showingAddError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .onAppear { accounts = preferences.accounts }
    }

    // MARK: - Bindings

    private func labelBinding(for account: TrackedAccount) -> Binding<String> {
        Binding(
            get: { account.label },
            set: { newValue in
                var updated = account
                updated.label = newValue
                preferences.updateAccount(updated)
                accounts = preferences.accounts
                onChange()
            }
        )
    }

    // MARK: - Actions

    private func addAccount() {
        showingAddError = nil
        let panel = NSOpenPanel()
        panel.title = "Select a Claude config directory"
        panel.message = "Pick a CLAUDE_CONFIG_DIR (e.g. ~/.claude-work)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: TrackedAccount.realHome)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Create a security-scoped bookmark so access persists across launches.
        let bookmark: Data?
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            showingAddError = "Couldn't create bookmark: \(error.localizedDescription)"
            return
        }

        let label = defaultLabel(from: url.lastPathComponent)
        let account = TrackedAccount(
            label: label,
            configDir: url.path,
            bookmarkData: bookmark
        )
        preferences.addAccount(account)
        accounts = preferences.accounts
        onChange()
    }

    private func remove(_ account: TrackedAccount) {
        preferences.removeAccount(id: account.id)
        accounts = preferences.accounts
        onChange()
    }

    // MARK: - Helpers

    /// Derives a default label from the directory name: `.claude-work` → `Work`,
    /// `.claude` → `Default`, anything else → the basename.
    private func defaultLabel(from dirName: String) -> String {
        if dirName == ".claude" { return "Default" }
        if dirName.hasPrefix(".claude-") {
            return String(dirName.dropFirst(".claude-".count)).capitalized
        }
        return dirName
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: TrackedAccount.realHome, with: "~")
    }
}
