import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hostingView: NSHostingView<MenuBarLabel>!

    let coordinator = AppCoordinator()
    let preferences = Preferences.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        coordinator.start()
        registerHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        GlobalHotkey.shared.unregister()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let label = MenuBarLabel(coordinator: coordinator, preferences: preferences)
        let host = NSHostingView(rootView: label)
        host.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView = host

        if let button = statusItem.button {
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 10)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRoot(
                coordinator: coordinator,
                preferences: preferences,
                onSettingsChange: { [weak self] in
                    self?.coordinator.reschedule()
                    self?.registerHotkey()
                }
            )
        )
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        GlobalHotkey.shared.register(
            keyCode: UInt32(preferences.hotkeyKeyCode),
            modifiers: UInt32(preferences.hotkeyModifiers)
        ) { [weak self] in
            self?.togglePopover(nil)
        }
    }
}
