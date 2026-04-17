import Foundation

/// Reads subscription usage from a `claudewatch-usage.json` file written by
/// the Claude Code statusline hook. Supports reading from any
/// `CLAUDE_CONFIG_DIR` — either the default `~/.claude` (covered by the app's
/// static entitlement) or a user-chosen alternate directory, accessed via a
/// security-scoped bookmark stored on the `TrackedAccount`.
struct QuotaSyncClient {

    let filePath: String

    init(filePath: String = (TrackedAccount.realHome as NSString)
            .appendingPathComponent(".claude/claudewatch-usage.json")) {
        self.filePath = filePath
    }

    func read() -> QuotaState? {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return nil
        }
        return QuotaState.from(data: data)
    }

    /// Read the usage JSON for a tracked account. For accounts with a
    /// security-scoped bookmark, resolves the bookmark and accesses the file
    /// inside the sandboxed scope. Accounts with no bookmark (the default
    /// `~/.claude`) are read directly via the static entitlement.
    static func read(account: TrackedAccount) -> QuotaState? {
        guard let data = account.bookmarkData else {
            return QuotaSyncClient(filePath: account.usageFilePath).read()
        }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }

        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        // The bookmark may resolve to either the directory or the JSON file
        // itself, depending on what the user picked. Handle both.
        let usageURL: URL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            usageURL = url.appendingPathComponent("claudewatch-usage.json")
        } else {
            usageURL = url
        }

        guard let fileData = try? Data(contentsOf: usageURL) else { return nil }
        return QuotaState.from(data: fileData)
    }
}
