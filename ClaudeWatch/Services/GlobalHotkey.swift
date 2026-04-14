import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via Carbon's `RegisterEventHotKey`. The handler
/// is invoked on the main thread. Native, zero deps.
///
/// Safety: the event handler callback holds an `Unmanaged.passUnretained` pointer
/// to `self`. This is safe because `GlobalHotkey.shared` is a module-level
/// singleton that lives for the entire process lifetime.
final class GlobalHotkey {

    typealias Handler = () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = OSType(0x434C5742) // "CLWB"
    private let id: UInt32 = 1
    private var handler: Handler?

    static let shared = GlobalHotkey()

    /// Registers (or re-registers) the hotkey. `keyCode` is a Carbon virtual
    /// key code; `modifiers` is a Carbon-style mask (cmdKey, shiftKey, etc.).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) -> Bool {
        unregister()
        self.handler = handler

        // Install a single application-wide event handler the first time around.
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: OSType(kEventHotKeyPressed))
            let cb: EventHandlerUPP = { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }
                let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr, hkID.signature == me.signature, hkID.id == me.id {
                    DispatchQueue.main.async { me.handler?() }
                }
                return noErr
            }
            var ref: EventHandlerRef?
            InstallEventHandler(
                GetApplicationEventTarget(),
                cb, 1, &spec,
                Unmanaged.passUnretained(self).toOpaque(),
                &ref
            )
            self.eventHandler = ref
        }

        let hkID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { return false }
        self.hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    // MARK: - NSEvent ↔ Carbon modifier conversion

    /// Convert AppKit `NSEvent.ModifierFlags` to Carbon modifiers used by
    /// `RegisterEventHotKey`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Reverse of `carbonModifiers(from:)` so the SwiftUI recorder can render
    /// the stored chord.
    static func appKitModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        if carbon & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if carbon & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}
