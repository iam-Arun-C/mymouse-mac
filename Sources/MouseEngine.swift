import Foundation
import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
import ApplicationServices

final class MouseEngine: ObservableObject {
    static let shared = MouseEngine()

    // MARK: - Published State
    @Published var isEngineEnabled: Bool = true {
        didSet { markUnsaved() }
    }
    @Published var hasAccessibilityPermission: Bool = false
    @Published var swapSideButtons: Bool = false {
        didSet { markUnsaved() }
    }
    @Published var mouseScrollMode: MouseScrollMode = .windowsStyle {
        didSet { markUnsaved() }
    }
    @Published var runInBackgroundWithoutDock: Bool = true {
        didSet {
            UserDefaults.standard.set(runInBackgroundWithoutDock, forKey: bgDockKey)
            updateLaunchAgentIfNeeded()
        }
    }

    // Explicit Save state
    @Published var hasUnsavedChanges: Bool = false
    @Published var saveSuccessPulse: Bool = false

    // Multi-Tap (1x, 2x, 3x) UI Selection & Live Detection
    @Published var selectedTapMode: TapCountKind = .single
    @Published var lastDetectedTapCount: Int = 1

    // Live Visual Monitor State (Active when Studio window is open)
    var isStudioWindowVisible: Bool = true {
        didSet {
            if isStudioWindowVisible {
                setupVisualMonitors()
            } else {
                removeVisualMonitors()
                pressedButtons.removeAll()
            }
        }
    }
    weak var studioWindowRef: NSWindow? = nil

    @Published var pressedButtons: Set<Int> = []
    @Published var lastDetectedButton: MouseButtonKind? = nil
    @Published var highlightedButtonForConfig: MouseButtonKind? = .sideForward

    // Profiles & Custom Keys Library
    @Published var profiles: [AppProfile] = [] {
        didSet { markUnsaved() }
    }
    @Published var selectedProfileID: UUID? = nil

    @Published var savedCustomKeys: [SavedCustomKey] = [] {
        didSet { markUnsaved() }
    }

    @Published var currentFrontmostAppName: String = "Finder"
    @Published var currentFrontmostBundleID: String = "com.apple.finder"

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var globalVisualMonitor: Any?
    private var permissionTimer: Timer?
    private var interceptedButtonsDown: Set<Int> = []
    private var isInitializing: Bool = true

    // Multi-tap state tracking (for 1x / 2x / 3x tap detection)
    private var tapCountsByButton: [Int: Int] = [:]
    private var lastTapTimestampByButton: [Int: TimeInterval] = [:]
    private var pendingTapWorkItems: [Int: DispatchWorkItem] = [:]
    private let multiTapThreshold: TimeInterval = 0.26

    private let profilesKey = "MyMouse.ClickFlow.Profiles.v4"
    private let legacyProfilesKey = "MyMouse.ClickFlow.Profiles.v3"
    private let customKeysKey = "MyMouse.ClickFlow.CustomKeys.v4"
    private let enabledKey = "MyMouse.ClickFlow.Enabled.v4"
    private let swapKey = "MyMouse.ClickFlow.SwapSide.v4"
    private let scrollModeKey = "MyMouse.ClickFlow.ScrollMode.v4"
    private let bgDockKey = "MyMouse.ClickFlow.BgDock.v4"

    private init() {
        loadAllFromDisk()
        if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
        }
        isInitializing = false
        hasUnsavedChanges = false

        setupAppWorkspaceObserver()
        setupVisualMonitors()
        verifyAndStartEventTap(prompt: false)
        startPermissionPolling()
        updateLaunchAgentIfNeeded()
        ensureSpotlightAndApplicationsRegistration()
    }

    private func markUnsaved() {
        guard !isInitializing else { return }
        hasUnsavedChanges = true
        persistToDisk()
    }

    /// Explicit Save action triggered by the user clicking the Save button
    func saveAllChanges() {
        persistToDisk()
        if eventTap == nil {
            verifyAndStartEventTap(prompt: false)
        } else if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            hasUnsavedChanges = false
            saveSuccessPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            withAnimation {
                self?.saveSuccessPulse = false
            }
        }
    }

    // MARK: - Spotlight & /Applications Registration
    func ensureSpotlightAndApplicationsRegistration() {
        DispatchQueue.global(qos: .utility).async {
            let currentBundlePath = Bundle.main.bundlePath
            let targetAppPath = "/Applications/MyMouse.app"

            if currentBundlePath != targetAppPath && currentBundlePath.hasSuffix(".app") {
                if FileManager.default.isWritableFile(atPath: "/Applications") {
                    try? FileManager.default.removeItem(atPath: targetAppPath)
                    try? FileManager.default.copyItem(atPath: currentBundlePath, toPath: targetAppPath)
                }
            }

            let pathToIndex = FileManager.default.fileExists(atPath: targetAppPath) ? targetAppPath : currentBundlePath

            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            if FileManager.default.fileExists(atPath: lsregister) {
                let p1 = Process()
                p1.executableURL = URL(fileURLWithPath: lsregister)
                p1.arguments = ["-f", pathToIndex]
                try? p1.run()
                p1.waitUntilExit()
            }

            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
            p2.arguments = [pathToIndex]
            try? p2.run()
            p2.waitUntilExit()
        }
    }

    // MARK: - Profile & Custom Keys Management
    var selectedProfile: AppProfile? {
        get {
            if let id = selectedProfileID, let found = profiles.first(where: { $0.id == id }) {
                return found
            }
            return profiles.first
        }
        set {
            guard let updated = newValue,
                  let idx = profiles.firstIndex(where: { $0.id == updated.id }) else { return }
            profiles[idx] = updated
        }
    }

    func updateMapping(for profileID: UUID, button: MouseButtonKind, tapCount: TapCountKind = .single, mapping: ButtonMapping) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].setMapping(mapping, for: button, tapCount: tapCount)
    }

    func addProfile(_ profile: AppProfile) {
        if let existingIdx = profiles.firstIndex(where: { $0.bundleIdentifier.lowercased() == profile.bundleIdentifier.lowercased() }) {
            selectedProfileID = profiles[existingIdx].id
            return
        }
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    func removeProfile(id: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        if profiles[idx].isGlobalDefault { return }
        profiles.remove(at: idx)
        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }
    }

    func addSavedCustomKey(name: String, combo: CustomKeyCombo) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? combo.displayString : trimmed
        let newKey = SavedCustomKey(name: finalName, combo: combo)
        savedCustomKeys.append(newKey)
    }

    func removeSavedCustomKey(id: UUID) {
        savedCustomKeys.removeAll { $0.id == id }
    }

    // MARK: - Effective Mapping Lookup (App-Specific first -> Global Fallback)
    func effectiveMapping(for button: MouseButtonKind, tapCount: TapCountKind, bundleID: String, appName: String) -> ButtonMapping {
        let lowerBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !lowerBundle.isEmpty {
            let appProfile = profiles.first(where: {
                let profBundle = $0.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !$0.isGlobalDefault && $0.isEnabled && !profBundle.isEmpty else { return false }
                return profBundle == lowerBundle ||
                       lowerBundle.hasPrefix(profBundle) ||
                       (!lowerName.isEmpty && $0.appName.lowercased() == lowerName)
            })

            if let specific = appProfile {
                let map = specific.mapping(for: button, tapCount: tapCount)
                if map.actionType != .passThrough {
                    return map
                }
            }
        }

        if let global = profiles.first(where: { $0.isGlobalDefault }) {
            return global.mapping(for: button, tapCount: tapCount)
        }

        return ButtonMapping(actionType: .passThrough)
    }

    func logicalButtonKind(for rawButtonNumber: Int) -> MouseButtonKind {
        if swapSideButtons {
            if rawButtonNumber == 3 { return .sideForward }
            if rawButtonNumber == 4 { return .sideBackward }
        }
        if let kind = MouseButtonKind(rawValue: rawButtonNumber) {
            return kind
        }
        return rawButtonNumber >= 5 ? .extra5 : .middle
    }

    // MARK: - Accessibility & Event Tap Verification
    func verifyAndStartEventTap(prompt: Bool) {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            startEventTap()
        }

        let isTapReady = (eventTap != nil)
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = isTapReady
            if isTapReady {
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
            } else if self.permissionTimer == nil {
                self.startPermissionPolling()
            }
        }
    }

    func requestAccessibilityPermission() {
        if eventTap == nil && !AXIsProcessTrusted() {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", "Accessibility", "com.mymouse.clickflow"]
            try? task.run()
            task.waitUntilExit()
        }

        verifyAndStartEventTap(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if AXIsProcessTrusted() {
                if self.eventTap == nil {
                    self.startEventTap()
                }
                if self.eventTap != nil {
                    self.hasAccessibilityPermission = true
                    t.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: - Active App Workspace Observer
    private func setupAppWorkspaceObserver() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            currentFrontmostAppName = front.localizedName ?? "Finder"
            currentFrontmostBundleID = front.bundleIdentifier ?? "com.apple.finder"
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self.currentFrontmostAppName = app.localizedName ?? "App"
                self.currentFrontmostBundleID = app.bundleIdentifier ?? ""
            }
        }
    }

    // MARK: - Live Visual Monitors (Only active while Studio Window is open for 0% background GPU)
    private func setupVisualMonitors() {
        guard localMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleVisualMouseEvent(event)
            if (event.type == .otherMouseDown || event.type == .otherMouseUp) && event.buttonNumber >= 3 {
                return nil
            }
            return event
        }

        globalVisualMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleVisualMouseEvent(event)
        }
    }

    private func removeVisualMonitors() {
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalVisualMonitor {
            NSEvent.removeMonitor(global)
            globalVisualMonitor = nil
        }
    }

    private func handleVisualMouseEvent(_ event: NSEvent) {
        guard isStudioWindowVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isStudioWindowVisible else { return }
            let rawBtn = event.buttonNumber
            let kind = self.logicalButtonKind(for: rawBtn)

            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                self.pressedButtons.insert(kind.rawValue)
                self.lastDetectedButton = kind
                if MouseButtonKind.primaryConfigurableButtons.contains(kind) {
                    self.highlightedButtonForConfig = kind
                }
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                self.pressedButtons.remove(kind.rawValue)
            default:
                break
            }
        }
    }

    // MARK: - Dedicated Mouse, Scroll Wheel & Modifier Flags CGEventTap
    func startEventTap() {
        if let existingTap = eventTap {
            CGEvent.tapEnable(tap: existingTap, enable: true)
            return
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: mouseEventTapCallback,
            userInfo: selfPtr
        ) else {
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = true
        }
    }

    fileprivate func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Check fn + Command hotkey via low-level flagsChanged (works in 100% of apps & full-screen!)
        if type == .flagsChanged {
            ClipboardManager.shared.handleCGFlagsChanged(event.flags)
            return Unmanaged.passUnretained(event)
        }

        guard isEngineEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // MARK: 1. Independent Trackpad vs External Mouse Scroll Wheel Control
        if type == .scrollWheel {
            guard mouseScrollMode != .macDefault else {
                return Unmanaged.passUnretained(event)
            }

            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

            if isContinuous != 0 || scrollPhase != 0 || momentumPhase != 0 {
                return Unmanaged.passUnretained(event)
            }

            if mouseScrollMode == .disableWheel {
                return nil
            }

            let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let pd1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let fd1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)

            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -d1)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pd1)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fd1)
            return Unmanaged.passUnretained(event)
        }

        // MARK: 2. Custom Mouse Buttons + Multi-Tap (1x, 2x, 3x) Control
        let rawButtonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard rawButtonNumber >= 2 else {
            return Unmanaged.passUnretained(event)
        }

        let logicalKind = logicalButtonKind(for: rawButtonNumber)

        // Track multi-tap count on mouseDown
        var currentTapStreak = 1
        if type == .otherMouseDown {
            let now = ProcessInfo.processInfo.systemUptime
            let lastTime = lastTapTimestampByButton[rawButtonNumber] ?? 0
            if now - lastTime <= multiTapThreshold {
                currentTapStreak = min(3, (tapCountsByButton[rawButtonNumber] ?? 1) + 1)
            } else {
                currentTapStreak = 1
            }
            tapCountsByButton[rawButtonNumber] = currentTapStreak
            lastTapTimestampByButton[rawButtonNumber] = now
        }

        if isStudioWindowVisible {
            let detectedStreak = currentTapStreak
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isStudioWindowVisible else { return }
                if type == .otherMouseDown {
                    self.pressedButtons.insert(logicalKind.rawValue)
                    self.lastDetectedButton = logicalKind
                    self.lastDetectedTapCount = detectedStreak
                    if MouseButtonKind.primaryConfigurableButtons.contains(logicalKind) {
                        self.highlightedButtonForConfig = logicalKind
                    }
                } else if type == .otherMouseUp {
                    self.pressedButtons.remove(logicalKind.rawValue)
                }
            }
        }

        // Only swallow for Studio testing if the Studio window is visible AND the cursor is physically inside the Studio window!
        if isStudioWindowVisible,
           let studioWin = studioWindowRef,
           studioWin.isVisible,
           NSPointInRect(NSEvent.mouseLocation, studioWin.frame) {
            return rawButtonNumber >= 3 ? nil : Unmanaged.passUnretained(event)
        }

        if type == .otherMouseUp {
            if interceptedButtonsDown.contains(rawButtonNumber) {
                interceptedButtonsDown.remove(rawButtonNumber)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDragged {
            if interceptedButtonsDown.contains(rawButtonNumber) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .otherMouseDown else {
            return Unmanaged.passUnretained(event)
        }

        // Determine active external application (even if MyMouse was just closed!)
        let frontApp = NSWorkspace.shared.frontmostApplication
        let targetBundleID: String
        let targetAppName: String
        if let fBundle = frontApp?.bundleIdentifier, fBundle != Bundle.main.bundleIdentifier {
            targetBundleID = fBundle
            targetAppName = frontApp?.localizedName ?? currentFrontmostAppName
        } else {
            targetBundleID = currentFrontmostBundleID
            targetAppName = currentFrontmostAppName
        }

        let singleMap = effectiveMapping(for: logicalKind, tapCount: .single, bundleID: targetBundleID, appName: targetAppName)
        let doubleMap = effectiveMapping(for: logicalKind, tapCount: .double, bundleID: targetBundleID, appName: targetAppName)
        let tripleMap = effectiveMapping(for: logicalKind, tapCount: .triple, bundleID: targetBundleID, appName: targetAppName)

        let anyMultiTapSet = doubleMap.isConfigured || tripleMap.isConfigured

        // Fast path: Only 1x Single Tap is configured -> Execute immediately!
        if !anyMultiTapSet {
            switch singleMap.actionType {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .disabled:
                interceptedButtonsDown.insert(rawButtonNumber)
                return nil
            default:
                interceptedButtonsDown.insert(rawButtonNumber)
                KeyCodeHelper.execute(singleMap)
                return nil
            }
        }

        // Multi-Tap Path (2x Double Tap or 3x Triple Tap is configured on this button)
        interceptedButtonsDown.insert(rawButtonNumber)
        pendingTapWorkItems[rawButtonNumber]?.cancel()

        if currentTapStreak == 3 {
            tapCountsByButton[rawButtonNumber] = 0
            let chosen = tripleMap.isConfigured ? tripleMap : (doubleMap.isConfigured ? doubleMap : singleMap)
            KeyCodeHelper.execute(chosen)
            return nil
        } else if currentTapStreak == 2 && !tripleMap.isConfigured {
            tapCountsByButton[rawButtonNumber] = 0
            let chosen = doubleMap.isConfigured ? doubleMap : singleMap
            KeyCodeHelper.execute(chosen)
            return nil
        }

        let capturedStreak = currentTapStreak
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.tapCountsByButton[rawButtonNumber] = 0
            if capturedStreak == 2 {
                let chosen = doubleMap.isConfigured ? doubleMap : singleMap
                KeyCodeHelper.execute(chosen)
            } else {
                KeyCodeHelper.execute(singleMap)
            }
        }
        pendingTapWorkItems[rawButtonNumber] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + multiTapThreshold, execute: workItem)
        return nil
    }

    // MARK: - Background Keep-Alive LaunchAgent
    func updateLaunchAgentIfNeeded() {
        let launchAgentsDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
        let plistPath = (launchAgentsDir as NSString).appendingPathComponent("com.mymouse.clickflow.plist")

        if runInBackgroundWithoutDock {
            let appExecPath = FileManager.default.fileExists(atPath: "/Applications/MyMouse.app/Contents/MacOS/MyMouse")
                ? "/Applications/MyMouse.app/Contents/MacOS/MyMouse"
                : (Bundle.main.executablePath ?? "/Applications/MyMouse.app/Contents/MacOS/MyMouse")
            try? FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.mymouse.clickflow</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appExecPath)</string>
                    <string>--background</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <dict>
                    <key>SuccessfulExit</key>
                    <false/>
                </dict>
            </dict>
            </plist>
            """
            try? plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: plistPath)
        }
    }

    // MARK: - Persistence
    private func persistToDisk() {
        UserDefaults.standard.set(isEngineEnabled, forKey: enabledKey)
        UserDefaults.standard.set(swapSideButtons, forKey: swapKey)
        UserDefaults.standard.set(mouseScrollMode.rawValue, forKey: scrollModeKey)
        UserDefaults.standard.set(runInBackgroundWithoutDock, forKey: bgDockKey)

        if let profData = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(profData, forKey: profilesKey)
        }
        if let keysData = try? JSONEncoder().encode(savedCustomKeys) {
            UserDefaults.standard.set(keysData, forKey: customKeysKey)
        }
    }

    private func loadAllFromDisk() {
        if UserDefaults.standard.object(forKey: enabledKey) != nil {
            isEngineEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
        if UserDefaults.standard.object(forKey: swapKey) != nil {
            swapSideButtons = UserDefaults.standard.bool(forKey: swapKey)
        }
        if let savedScroll = UserDefaults.standard.string(forKey: scrollModeKey),
           let mode = MouseScrollMode(rawValue: savedScroll) {
            mouseScrollMode = mode
        }
        if UserDefaults.standard.object(forKey: bgDockKey) != nil {
            runInBackgroundWithoutDock = UserDefaults.standard.bool(forKey: bgDockKey)
        }

        if let data = UserDefaults.standard.data(forKey: profilesKey) ?? UserDefaults.standard.data(forKey: legacyProfilesKey),
           let decoded = try? JSONDecoder().decode([AppProfile].self, from: data),
           !decoded.isEmpty {
            profiles = decoded
        } else {
            profiles = Self.createDefaultProfiles()
        }

        if let data = UserDefaults.standard.data(forKey: customKeysKey),
           let decoded = try? JSONDecoder().decode([SavedCustomKey].self, from: data) {
            savedCustomKeys = decoded
        } else {
            savedCustomKeys = Self.createDefaultCustomKeys()
        }
    }

    static func createDefaultProfiles() -> [AppProfile] {
        var globalMappings: [Int: ButtonMapping] = [:]
        globalMappings[MouseButtonKind.sideForward.rawValue] = ButtonMapping(actionType: .copy)
        globalMappings[MouseButtonKind.sideBackward.rawValue] = ButtonMapping(actionType: .paste)
        globalMappings[MouseButtonKind.middle.rawValue] = ButtonMapping(actionType: .passThrough)

        let globalProfile = AppProfile(
            appName: "Global (All Apps)",
            bundleIdentifier: "*",
            appPath: nil,
            isEnabled: true,
            mappings: globalMappings
        )
        return [globalProfile]
    }

    static func createDefaultCustomKeys() -> [SavedCustomKey] {
        return [
            SavedCustomKey(name: "Copy", combo: CustomKeyCombo(keyCode: UInt16(kVK_ANSI_C), command: true, shift: false, option: false, control: false)),
            SavedCustomKey(name: "Paste", combo: CustomKeyCombo(keyCode: UInt16(kVK_ANSI_V), command: true, shift: false, option: false, control: false)),
            SavedCustomKey(name: "Print", combo: CustomKeyCombo(keyCode: UInt16(kVK_ANSI_P), command: true, shift: false, option: false, control: false)),
            SavedCustomKey(name: "Undo", combo: CustomKeyCombo(keyCode: UInt16(kVK_ANSI_Z), command: true, shift: false, option: false, control: false))
        ]
    }
}

// MARK: - C Callback for CGEventTap
private func mouseEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let engine = Unmanaged<MouseEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handleCGEvent(proxy: proxy, type: type, event: event)
}
