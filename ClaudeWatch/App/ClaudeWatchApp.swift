import SwiftUI

@main
struct ClaudeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Menu bar app — no main window. Settings is reachable via the popover.
        Settings { EmptyView() }
    }
}
