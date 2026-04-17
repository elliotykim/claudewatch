import Foundation

/// One Claude account that ClaudeWatch tracks usage for. Each account has its
/// own `CLAUDE_CONFIG_DIR` on disk (e.g. `~/.claude-work`) with its own
/// `claudewatch-usage.json` written by its own statusline hook.
///
/// `configDir` is the absolute path to the config directory. `bookmarkData`
/// is the security-scoped bookmark for that directory, required for sandboxed
/// read access to anything outside the default `~/.claude` entitlement.
/// The default account (`~/.claude`) is covered by the app's static
/// entitlement and carries no bookmark.
struct TrackedAccount: Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var configDir: String
    var bookmarkData: Data?

    init(id: UUID = UUID(), label: String, configDir: String, bookmarkData: Data? = nil) {
        self.id = id
        self.label = label
        self.configDir = configDir
        self.bookmarkData = bookmarkData
    }

    var usageFilePath: String {
        (configDir as NSString).appendingPathComponent("claudewatch-usage.json")
    }

    /// The real user home directory, bypassing sandbox container redirection.
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    static var defaultConfigDir: String {
        (realHome as NSString).appendingPathComponent(".claude")
    }

    /// The account seeded on first launch: points at `~/.claude`, no bookmark
    /// (read access is granted by the static entitlement).
    static func seedDefault() -> TrackedAccount {
        TrackedAccount(label: "Default", configDir: defaultConfigDir)
    }
}
