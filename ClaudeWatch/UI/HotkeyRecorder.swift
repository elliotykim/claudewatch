import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A minimal, clickable field that captures the next key chord and stores it
/// in Preferences. Native — uses `NSEvent.addLocalMonitorForEvents`.
struct HotkeyRecorder: View {
    @ObservedObject var preferences: Preferences
    var onChange: () -> Void

    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleCapture) {
            HStack {
                Image(systemName: capturing ? "record.circle" : "keyboard")
                Text(capturing ? "Press a chord…" : displayString)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .buttonStyle(.bordered)
        .onDisappear { stopCapture() }
    }

    private var displayString: String {
        let mods = GlobalHotkey.appKitModifiers(from: UInt32(preferences.hotkeyModifiers))
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        s += keyName(for: UInt32(preferences.hotkeyKeyCode))
        return s
    }

    private func toggleCapture() {
        if capturing { stopCapture() } else { startCapture() }
    }

    private func startCapture() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty == false else {
                return event // require at least one modifier
            }
            preferences.hotkeyKeyCode = Int(event.keyCode)
            preferences.hotkeyModifiers = Int(GlobalHotkey.carbonModifiers(from: event.modifierFlags))
            stopCapture()
            onChange()
            return nil
        }
    }

    private func stopCapture() {
        capturing = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func keyName(for keyCode: UInt32) -> String {
        // Tiny lookup for common codes; everything else falls back to "key \(code)".
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_Space:  return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        default: return "key \(keyCode)"
        }
    }
}
