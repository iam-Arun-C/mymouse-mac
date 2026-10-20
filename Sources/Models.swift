import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Tap Count Multi-Function (1x Single, 2x Double, 3x Triple Tap)
enum TapCountKind: Int, CaseIterable, Codable, Identifiable {
    case single = 1
    case double = 2
    case triple = 3

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .single: return "1× Tap"
        case .double: return "2× Tap"
        case .triple: return "3× Tap"
        }
    }

    var fullTitle: String {
        switch self {
        case .single: return "Single Tap (1×)"
        case .double: return "Double Tap (2×)"
        case .triple: return "Triple Tap (3×)"
        }
    }
}

// MARK: - Mouse Scroll Wheel Mode (Independent from Trackpad Natural Scrolling)
enum MouseScrollMode: String, CaseIterable, Codable, Identifiable {
    case windowsStyle = "windowsStyle"       // Disables Natural Scrolling on Mouse ONLY (keeps Trackpad Natural ON)
    case macDefault = "macDefault"           // Standard macOS linked behavior
    case disableWheel = "disableWheel"       // Completely turns off mouse scroll wheel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowsStyle: return "Windows Scroll (Trackpad Natural ON)"
        case .macDefault: return "macOS Default (Linked)"
        case .disableWheel: return "Disable Mouse Wheel Completely"
        }
    }

    var shortBadge: String {
        switch self {
        case .windowsStyle: return "Win Scroll"
        case .macDefault: return "Mac Default"
        case .disableWheel: return "Wheel Off"
        }
    }
}

// MARK: - Mouse Button Identifier
enum MouseButtonKind: Int, CaseIterable, Codable, Identifiable {
    case left = 0
    case right = 1
    case middle = 2        // Scroll Wheel Click
    case sideBackward = 3  // Rear Thumb Button (Btn 3)
    case sideForward = 4   // Front Thumb Button (Btn 4)
    case extra5 = 5        // Extra Gaming Button

    var id: Int { rawValue }

    static var primaryConfigurableButtons: [MouseButtonKind] {
        [.sideForward, .sideBackward, .middle]
    }

    var displayName: String {
        switch self {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Wheel"
        case .sideBackward: return "Backward"
        case .sideForward: return "Forward"
        case .extra5: return "Extra Button"
        }
    }

    var shortName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        case .sideBackward: return "Backward"
        case .sideForward: return "Forward"
        case .extra5: return "Extra"
        }
    }

    var tooltipInfo: String {
        switch self {
        case .left: return "Standard Left Click"
        case .right: return "Standard Right Click"
        case .middle: return "Middle Scroll Wheel Click — supports 1×, 2×, and 3× tap actions"
        case .sideBackward: return "Lower Side Thumb Button — supports 1×, 2×, and 3× tap actions"
        case .sideForward: return "Upper Side Thumb Button — supports 1×, 2×, and 3× tap actions"
        case .extra5: return "Extra Gaming Button"
        }
    }

    var iconName: String {
        switch self {
        case .left, .right: return "computermouse"
        case .middle: return "circle.grid.cross.fill"
        case .sideBackward: return "arrow.backward.circle.fill"
        case .sideForward: return "arrow.forward.circle.fill"
        case .extra5: return "bolt.circle.fill"
        }
    }
}

// MARK: - Action Types
enum ButtonActionType: String, CaseIterable, Codable, Identifiable {
    case passThrough = "passThrough"
    case disabled = "disabled"
    case copy = "copy"
    case paste = "paste"
    case cut = "cut"
    case undo = "undo"
    case redo = "redo"
    case selectAll = "selectAll"
    case save = "save"
    case printDoc = "printDoc"
    case browserBack = "browserBack"
    case browserForward = "browserForward"
    case newTab = "newTab"
    case closeTab = "closeTab"
    case missionControl = "missionControl"
    case showDesktop = "showDesktop"
    case screenshot = "screenshot"
    case clipboardHistory = "clipboardHistory"
    case customShortcut = "customShortcut"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passThrough: return "None / Default"
        case .disabled: return "Block Button"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .cut: return "Cut"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .selectAll: return "Select All"
        case .save: return "Save"
        case .printDoc: return "Print"
        case .browserBack: return "Browser Back"
        case .browserForward: return "Browser Forward"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        case .screenshot: return "Screenshot"
        case .clipboardHistory: return "Clipboard Popup"
        case .customShortcut: return "Custom Key..."
        }
    }

    var badgeText: String {
        switch self {
        case .passThrough: return "Off"
        case .disabled: return "Blocked"
        case .copy: return "⌘C"
        case .paste: return "⌘V"
        case .cut: return "⌘X"
        case .undo: return "⌘Z"
        case .redo: return "⇧⌘Z"
        case .selectAll: return "⌘A"
        case .save: return "⌘S"
        case .printDoc: return "⌘P"
        case .browserBack: return "⌘["
        case .browserForward: return "⌘]"
        case .newTab: return "⌘T"
        case .closeTab: return "⌘W"
        case .missionControl: return "⌃↑"
        case .showDesktop: return "F11"
        case .screenshot: return "⇧⌘4"
        case .clipboardHistory: return "fn+⌘"
        case .customShortcut: return "Custom"
        }
    }
}

// MARK: - Custom Key Combination
struct CustomKeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(KeyCodeHelper.keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        return flags
    }
}

// MARK: - User-Created Custom Key Preset
struct SavedCustomKey: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var combo: CustomKeyCombo

    init(id: UUID = UUID(), name: String, combo: CustomKeyCombo) {
        self.id = id
        self.name = name
        self.combo = combo
    }
}

// MARK: - Button Mapping Configuration
struct ButtonMapping: Codable, Equatable {
    var actionType: ButtonActionType
    var customCombo: CustomKeyCombo?
    var customLabel: String?

    init(actionType: ButtonActionType = .passThrough, customCombo: CustomKeyCombo? = nil, customLabel: String? = nil) {
        self.actionType = actionType
        self.customCombo = customCombo
        self.customLabel = customLabel
    }

    var isConfigured: Bool {
        actionType != .passThrough
    }

    var effectiveBadge: String {
        if actionType == .customShortcut, let combo = customCombo {
            return combo.displayString
        }
        return actionType.badgeText
    }

    var effectiveTitle: String {
        if actionType == .customShortcut {
            if let label = customLabel, !label.isEmpty {
                return "\(label) (\(customCombo?.displayString ?? ""))"
            }
            if let combo = customCombo {
                return combo.displayString
            }
        }
        return actionType.title
    }
}

// MARK: - Per-Application Profile (Supports 1x Single, 2x Double, and 3x Triple Tap!)
struct AppProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var appName: String
    var bundleIdentifier: String // "*" for Global Default
    var appPath: String?
    var isEnabled: Bool
    var mappings: [Int: ButtonMapping]            // 1x Single Tap
    var doubleTapMappings: [Int: ButtonMapping]   // 2x Double Tap
    var tripleTapMappings: [Int: ButtonMapping]   // 3x Triple Tap

    var isGlobalDefault: Bool {
        bundleIdentifier == "*"
    }

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        appPath: String? = nil,
        isEnabled: Bool = true,
        mappings: [Int: ButtonMapping] = [:],
        doubleTapMappings: [Int: ButtonMapping] = [:],
        tripleTapMappings: [Int: ButtonMapping] = [:]
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.isEnabled = isEnabled
        self.mappings = mappings
        self.doubleTapMappings = doubleTapMappings
        self.tripleTapMappings = tripleTapMappings
    }

    func mapping(for button: MouseButtonKind, tapCount: TapCountKind = .single) -> ButtonMapping {
        switch tapCount {
        case .single:
            return mappings[button.rawValue] ?? ButtonMapping(actionType: .passThrough)
        case .double:
            return doubleTapMappings[button.rawValue] ?? ButtonMapping(actionType: .passThrough)
        case .triple:
            return tripleTapMappings[button.rawValue] ?? ButtonMapping(actionType: .passThrough)
        }
    }

    mutating func setMapping(_ mapping: ButtonMapping, for button: MouseButtonKind, tapCount: TapCountKind = .single) {
        switch tapCount {
        case .single:
            mappings[button.rawValue] = mapping
        case .double:
            doubleTapMappings[button.rawValue] = mapping
        case .triple:
            tripleTapMappings[button.rawValue] = mapping
        }
    }

    func hasMultiTapConfigured(for button: MouseButtonKind) -> Bool {
        let d = mapping(for: button, tapCount: .double)
        let t = mapping(for: button, tapCount: .triple)
        return d.isConfigured || t.isConfigured
    }
}

// MARK: - Clipboard Hotkey Mode
enum ClipboardHotkeyMode: String, CaseIterable, Codable, Identifiable {
    case fnCommand = "fnCommand"         // fn + Command (Globe + ⌘)
    case optionV = "optionV"             // Option + V (⌥ + V)
    case cmdShiftV = "cmdShiftV"         // Command + Shift + V (⇧ + ⌘ + V)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fnCommand: return "fn + ⌘"
        case .optionV: return "⌥ + V"
        case .cmdShiftV: return "⇧ + ⌘ + V"
        }
    }
}
