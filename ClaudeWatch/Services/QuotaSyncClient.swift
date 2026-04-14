import Foundation

/// Reads subscription usage from `~/.claude/claudewatch-usage.json`,
/// written by the Claude Code statusline hook.
struct QuotaSyncClient {

    let filePath: String

    /// The real user home directory, bypassing sandbox container redirection.
    private static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    init(filePath: String = (QuotaSyncClient.realHome as NSString)
            .appendingPathComponent(".claude/claudewatch-usage.json")) {
        self.filePath = filePath
    }

    func read() -> QuotaState? {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return nil
        }
        return QuotaState.from(data: data)
    }
}
