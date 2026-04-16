# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```sh
# Build
xcodebuild -scheme ClaudeWatch -configuration Debug build

# Run tests
xcodebuild -scheme ClaudeWatch test -destination 'platform=macOS'
```

Or open `ClaudeWatch.xcodeproj` in Xcode and Cmd-R / Cmd-U.

## Architecture

ClaudeWatch is a sandboxed macOS menu-bar app (LSUIElement) with zero external dependencies. Everything is Swift 5 / SwiftUI / AppKit targeting macOS 14+.

**Data flow:** `AppDelegate` → `AppCoordinator` → three client services → `@Published` state → SwiftUI views.

- **AppDelegate** owns the `NSStatusItem` (menu bar) and `NSPopover`. The menu bar content is a SwiftUI `MenuBarLabel` embedded in `NSHostingView`; the popover wraps `PopoverRoot` in `NSHostingController`.
- **AppCoordinator** (`@MainActor`, `ObservableObject`) runs two scheduled timers (quota sync + status poll), a sleep/wake observer, and publishes `quota`, `status`, and `uptime` state that views observe.
- **Three services** provide data:
  - `QuotaSyncClient` — reads `~/.claude/claudewatch-usage.json` (local file, written by the Claude Code statusline hook). Uses `getpwuid()` to get the real home directory, bypassing sandbox container redirection.
  - `StatusClient` — polls `status.claude.com/api/v2/components.json` for Claude Code component status.
  - `UptimeClient` — fetches paginated incidents from the Statuspage API, merges overlapping time ranges for downtime calculation, and scrapes the official 90-day uptime percentage from the status page HTML via regex. The scraping is fragile; if the DOM changes it fails silently.
- **Preferences** is a `@MainActor` singleton backed by `@AppStorage` / `UserDefaults`. Enum preferences use `String` raw values for `RawRepresentable` conformance.

**Menu bar:** `NSStatusItem` with `variableLength`. The button uses `sendAction(on: [.leftMouseUp, .rightMouseUp])` for both click types. `GlobalHotkey` uses Carbon's `RegisterEventHotKey` API — note the AppKit ↔ Carbon modifier flag conversion.

**Popover:** `.transient` behavior (closes on outside click). `PopoverRoot` toggles between main view and settings via `@State`. Listens to `NSPopover.didCloseNotification` to reset back to main view on close. The settings `ScrollView` has `frame(minHeight: 400)` to prevent content collapse during menu bar relayout.

**Color system:** `GraphicColor` (menu bar graphic) and `BarColor` (popover progress bars) are separate enums with independent preferences. Both share a `dynamicColor(_:base:)` helper for threshold-based coloring (blue/yellow/orange/red by usage %).

## Gotchas

- **@MainActor is pervasive.** AppDelegate, AppCoordinator, Preferences, and all timer/observer callbacks must run on main. Services are main-agnostic.
- **Sandbox + home directory.** The app has a read-only exception for `~/.claude/` in entitlements, but `NSHomeDirectory()` returns the container path. `QuotaSyncClient` uses `getpwuid(getuid())` to resolve the real home.
- **1-second timer tick pattern.** `StatusSection` and `UsageSection` each have a `@State tick` + `Timer.publish(every: 1)` to force live relative-time updates. The `let _ = tick` in `body` is required to trigger re-evaluation.
- **Adding new Swift files** requires updating `project.pbxproj` — add entries in PBXFileReference, PBXBuildFile, the appropriate PBXGroup, and PBXSourcesBuildPhase.
- **Uptime HTML scraping** uses regex `id=\"uptime-percent-([a-z0-9]+)\">\s*<var[^>]*>([0-9.]+)</var>` against the status page. If Statuspage changes their DOM, this breaks silently and the 90-day percentage simply won't display.
