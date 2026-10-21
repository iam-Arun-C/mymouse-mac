import Foundation
import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum KeyCodeHelper {
    /// Dedicated high-priority serial queue for key synthesis so events never collide with mouse-down HID state.
    private static let keyQueue = DispatchQueue(label: "com.mymouse.clickflow.keysender", qos: .userInteractive)

    /// Executes the mapped action reliably across all macOS applications.
    static func execute(_ mapping: ButtonMapping) {
        switch mapping.actionType {
        case .passThrough, .disabled:
            break

        case .copy:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_C), flags: .maskCommand)
            ClipboardManager.shared.checkPasteboardSoon()
        case .paste:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
        case .cut:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_X), flags: .maskCommand)
            ClipboardManager.shared.checkPasteboardSoon()
        case .undo:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_Z), flags: .maskCommand)
        case .redo:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_Z), flags: [.maskCommand, .maskShift])
        case .selectAll:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_A), flags: .maskCommand)
        case .save:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_S), flags: .maskCommand)
        case .printDoc:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_P), flags: .maskCommand)

        case .browserBack:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_LeftBracket), flags: .maskCommand)
        case .browserForward:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_RightBracket), flags: .maskCommand)
        case .newTab:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_T), flags: .maskCommand)
        case .closeTab:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_W), flags: .maskCommand)

        case .missionControl:
            DispatchQueue.main.async {
                if !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app")) {
                    sendKeyCombo(keyCode: UInt16(kVK_UpArrow), flags: .maskControl)
                }
            }
        case .showDesktop:
            sendKeyCombo(keyCode: UInt16(kVK_F11), flags: [])
        case .screenshot:
            sendKeyCombo(keyCode: UInt16(kVK_ANSI_4), flags: [.maskCommand, .maskShift])

        case .clipboardHistory:
            DispatchQueue.main.async {
                ClipboardManager.shared.togglePopup()
            }

        case .customShortcut:
            if let combo = mapping.customCombo {
                sendKeyCombo(keyCode: combo.keyCode, flags: combo.cgEventFlags)
            }
        }
    }

    /// Synthesizes a hardware-accurate keyboard shortcut with modifier key-down/up framing and suppression bypass.
    /// Permits events during the post-mouse-click suppression interval so clicking a UI button to paste never drops ⌘V.
    static func sendKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        keyQueue.async {
            // Brief pause so any triggering mouse-up/down event clears the target app's runloop first
            usleep(8_000)

            let source = CGEventSource(stateID: .combinedSessionState)
            // CRITICAL: Permit synthetic keyboard events even immediately after a physical mouse click!
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateRemoteMouseDrag
            )

            // Strip any accidental fn / numeric-pad flags so ⌘V is received as a pure Command+V
            let cleanFlags = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

            // 1. Press required modifier keys explicitly
            if cleanFlags.contains(.maskCommand) {
                if let modDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true) {
                    modDown.flags = cleanFlags
                    modDown.post(tap: .cghidEventTap)
                }
            }
            if cleanFlags.contains(.maskShift) {
                if let modDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: true) {
                    modDown.flags = cleanFlags
                    modDown.post(tap: .cghidEventTap)
                }
            }
            if cleanFlags.contains(.maskAlternate) {
                if let modDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Option), keyDown: true) {
                    modDown.flags = cleanFlags
                    modDown.post(tap: .cghidEventTap)
                }
            }
            if cleanFlags.contains(.maskControl) {
                if let modDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: true) {
                    modDown.flags = cleanFlags
                    modDown.post(tap: .cghidEventTap)
                }
            }

            usleep(3_000)

            // 2. Press target key down
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                keyDown.flags = cleanFlags
                keyDown.post(tap: .cghidEventTap)
            }

            // Hold key for 8ms so all apps (Chrome, Electron, VS Code, Notes, Adobe) register the stroke cleanly
            usleep(8_000)

            // 3. Release target key up
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                keyUp.flags = cleanFlags
                keyUp.post(tap: .cghidEventTap)
            }

            usleep(3_000)

            // 4. Release modifier keys cleanly
            if cleanFlags.contains(.maskControl) {
                if let modUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: false) {
                    modUp.flags = []
                    modUp.post(tap: .cghidEventTap)
                }
            }
            if cleanFlags.contains(.maskAlternate) {
                if let modUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Option), keyDown: false) {
                    modUp.flags = []
                    modUp.post(tap: .cghidEventTap)
                }
            }
            if cleanFlags.contains(.maskShift) {
                if let modUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: false) {
                    modUp.flags = []
                    modUp.post(tap: .cghidEventTap)
                }
            }
            if cleanFlags.contains(.maskCommand) {
                if let modUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) {
                    modUp.flags = []
                    modUp.post(tap: .cghidEventTap)
                }
            }

            // Clean separation gap before any subsequent rapid key combo (e.g. instant Copy -> Paste)
            usleep(6_000)
        }
    }

    /// Converts a macOS virtual key code into a readable keycap label.
    static func keyName(for keyCode: UInt16) -> String {
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

        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"

        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"

        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "PgUp"
        case kVK_PageDown: return "PgDn"

        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        default: return "Key #\(keyCode)"
        }
    }
}
