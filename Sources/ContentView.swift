import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var engine: MouseEngine
    @ObservedObject var clipboard = ClipboardManager.shared

    @State private var showAddAppSheet: Bool = false
    @State private var recordingForButton: MouseButtonKind? = nil
    @State private var showCreateCustomKeySheet: Bool = false

    @Namespace private var profileSelectionNamespace
    @Namespace private var scrollModeSliderNamespace

    private var activeProfile: AppProfile {
        engine.selectedProfile ?? engine.profiles.first ?? MouseEngine.createDefaultProfiles()[0]
    }

    private var selectedTargetButton: MouseButtonKind {
        engine.highlightedButtonForConfig ?? .sideForward
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Uniform Obsidian Graphite Background (Standard Apple Pro Color Science)
            VisualEffectGlass(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.windowBgTop.opacity(0.92),
                    AppTheme.windowBgBottom.opacity(0.96)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Main 2-Column Minimalist Layout
            HStack(spacing: 14) {
                // LEFT SIDEBAR: App Status + Profiles + Mouse Scroll Slider + Notch Clipboard
                sidebarPanel
                    .frame(width: 248)

                // RIGHT WORKSPACE: Active Profile Header + Mouse Hardware Preview + Button Rows + Saved Keys
                VStack(spacing: 12) {
                    topActionBar

                    InteractiveMouseView(
                        engine: engine,
                        activeProfile: activeProfile,
                        onSelectButton: { kind in
                            engine.highlightedButtonForConfig = kind
                        }
                    )

                    // 3 Configurable Mouse Button Rows (Uniform Color Science & 1x / 2x / 3x Pills)
                    VStack(spacing: 8) {
                        ForEach(MouseButtonKind.primaryConfigurableButtons) { kind in
                            UniformButtonAssignmentRow(
                                buttonKind: kind,
                                activeProfile: activeProfile,
                                selectedTapMode: engine.selectedTapMode,
                                savedCustomKeys: engine.savedCustomKeys,
                                isPressed: engine.pressedButtons.contains(kind.rawValue),
                                isSelected: selectedTargetButton == kind,
                                onSelectRowAndTap: { tap in
                                    withAnimation(AppTheme.springSlider) {
                                        engine.highlightedButtonForConfig = kind
                                        engine.selectedTapMode = tap
                                    }
                                },
                                onUpdateMapping: { newMapping in
                                    engine.highlightedButtonForConfig = kind
                                    engine.updateMapping(
                                        for: activeProfile.id,
                                        button: kind,
                                        tapCount: engine.selectedTapMode,
                                        mapping: newMapping
                                    )
                                },
                                onRecordKey: {
                                    engine.highlightedButtonForConfig = kind
                                    recordingForButton = kind
                                }
                            )
                        }
                    }

                    // Saved Custom Keys Library Bar
                    customKeysBar
                }
            }
            .padding(16)

            // Instant Floating Smart Custom Tooltip HUD at Bottom Center
            SmartTooltipHUD()
                .padding(.bottom, 14)
        }
        .frame(minWidth: 840, idealWidth: 880, minHeight: 575, idealHeight: 595)
        .onAppear {
            engine.isStudioWindowVisible = true
        }
        .onDisappear {
            engine.isStudioWindowVisible = false
        }
        .sheet(isPresented: $showAddAppSheet) {
            AppPickerSheet(
                existingBundleIDs: Set(engine.profiles.map { $0.bundleIdentifier.lowercased() }),
                onSelectApp: { item in
                    let globalProf = engine.profiles.first(where: { $0.isGlobalDefault })
                    let newProfile = AppProfile(
                        appName: item.appName,
                        bundleIdentifier: item.bundleIdentifier,
                        appPath: item.appPath,
                        isEnabled: true,
                        mappings: globalProf?.mappings ?? [:],
                        doubleTapMappings: globalProf?.doubleTapMappings ?? [:],
                        tripleTapMappings: globalProf?.tripleTapMappings ?? [:]
                    )
                    withAnimation(AppTheme.springSlider) {
                        engine.addProfile(newProfile)
                    }
                    showAddAppSheet = false
                },
                onCancel: {
                    showAddAppSheet = false
                }
            )
        }
        .sheet(item: $recordingForButton) { buttonKind in
            ShortcutRecorderSheet(
                title: "Set \(engine.selectedTapMode.fullTitle) for \(buttonKind.shortName)",
                subtitle: "Profile: \(activeProfile.appName)",
                showNameField: false,
                recordedCombo: activeProfile.mapping(for: buttonKind, tapCount: engine.selectedTapMode).customCombo,
                onSave: { _, combo in
                    let updated = ButtonMapping(actionType: .customShortcut, customCombo: combo)
                    engine.updateMapping(
                        for: activeProfile.id,
                        button: buttonKind,
                        tapCount: engine.selectedTapMode,
                        mapping: updated
                    )
                    recordingForButton = nil
                },
                onCancel: {
                    recordingForButton = nil
                }
            )
        }
        .sheet(isPresented: $showCreateCustomKeySheet) {
            ShortcutRecorderSheet(
                title: "Create Custom Shortcut",
                subtitle: "Save your keyboard shortcut for 1-click assignment",
                showNameField: true,
                recordedCombo: nil,
                onSave: { name, combo in
                    engine.addSavedCustomKey(name: name, combo: combo)
                    let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let mapping = ButtonMapping(actionType: .customShortcut, customCombo: combo, customLabel: label.isEmpty ? nil : label)
                    engine.updateMapping(
                        for: activeProfile.id,
                        button: selectedTargetButton,
                        tapCount: engine.selectedTapMode,
                        mapping: mapping
                    )
                    showCreateCustomKeySheet = false
                },
                onCancel: {
                    showCreateCustomKeySheet = false
                }
            )
        }
    }

    // MARK: - Left Sidebar (Uniform Apple Settings Style)
    private var sidebarPanel: some View {
        LiquidGlassCard(cornerRadius: 16, tintColor: AppTheme.accent, isHighlighted: false) {
            VStack(alignment: .leading, spacing: 12) {
                // 1. App Brand + Master Engine Switch
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppTheme.accent)
                            .frame(width: 30, height: 30)
                        Image(systemName: "computermouse.fill")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("My Mouse")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(engine.isEngineEnabled ? AppTheme.success : AppTheme.textMuted)
                                .frame(width: 5.5, height: 5.5)
                            Text(engine.isEngineEnabled ? "Engine Active" : "Paused")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(engine.isEngineEnabled ? AppTheme.success : AppTheme.textMuted)
                        }
                    }

                    Spacer()

                    LiquidIconButton(
                        icon: "power",
                        tint: engine.isEngineEnabled ? AppTheme.success : AppTheme.danger,
                        isActive: engine.isEngineEnabled,
                        size: 28,
                        tooltipTitle: engine.isEngineEnabled ? "Mouse Engine: ON" : "Mouse Engine: PAUSED",
                        tooltipDetail: "Toggle all custom mouse button and scroll controls."
                    ) {
                        withAnimation(AppTheme.springSnappy) {
                            engine.isEngineEnabled.toggle()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                Divider().opacity(0.25)

                // 2. Application Profiles Header + Add App Button
                HStack {
                    Text("APPLICATION PROFILES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                        .tracking(0.6)

                    Spacer()

                    Button(action: { showAddAppSheet = true }) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Add App")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(AppTheme.accentSoft))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            SmartTooltipManager.shared.show(
                                icon: "plus.app.fill",
                                title: "Add Application Profile",
                                detail: "Assign custom mouse button shortcuts for a specific app (e.g. Chrome, Photoshop). Other apps use Global.",
                                tint: AppTheme.accent
                            )
                        } else {
                            SmartTooltipManager.shared.hide()
                        }
                    }
                }
                .padding(.horizontal, 14)

                // Profiles List with Gliding Selection Highlight (`matchedGeometryEffect`)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(engine.profiles) { profile in
                            UniformSidebarProfileRow(
                                profile: profile,
                                isSelected: activeProfile.id == profile.id,
                                namespace: profileSelectionNamespace,
                                onSelect: {
                                    withAnimation(AppTheme.springSlider) {
                                        engine.selectedProfileID = profile.id
                                    }
                                },
                                onDelete: {
                                    withAnimation(AppTheme.springSnappy) {
                                        engine.removeProfile(id: profile.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }

                Spacer(minLength: 0)

                Divider().opacity(0.25)

                // 3. Mouse Wheel Scroll Mode (With Gliding Liquid Glass Slider!)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Image(systemName: "arrow.up.and.down.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                        Text("Mouse Wheel Scroll")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text("Trackpad stays Natural")
                            .font(.system(size: 9.5))
                            .foregroundColor(AppTheme.textMuted)
                    }

                    // 3-Option Gliding Liquid Glass Slider: Windows | Mac | Off
                    HStack(spacing: 0) {
                        scrollModeButton(.windowsStyle, label: "Windows")
                        scrollModeButton(.macDefault, label: "Mac")
                        scrollModeButton(.disableWheel, label: "Wheel Off")
                    }
                    .padding(2.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.045))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(AppTheme.borderSubtle, lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 14)

                Divider().opacity(0.25)

                // 4. Compact Single-Row Clipboard Control (Clipboard • fn+⌘ • Open • Switch)
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(clipboard.isEnabled ? AppTheme.accent : AppTheme.textMuted)

                    Text("Clipboard")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()

                    Text("fn+⌘")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(clipboard.isEnabled ? AppTheme.textSecondary : AppTheme.textMuted)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.055))
                        )
                        .fixedSize()

                    Spacer(minLength: 4)

                    if clipboard.isEnabled {
                        Button(action: { clipboard.togglePopup() }) {
                            Text("Open")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.075))
                                        .overlay(
                                            Capsule()
                                                .stroke(AppTheme.borderSubtle, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }

                    // Compact Minimalist Sliding Toggle Switch
                    Button(action: {
                        withAnimation(AppTheme.springSlider) {
                            clipboard.isEnabled.toggle()
                        }
                    }) {
                        ZStack(alignment: clipboard.isEnabled ? .trailing : .leading) {
                            Capsule()
                                .fill(clipboard.isEnabled ? AppTheme.accent : Color.white.opacity(0.12))
                                .frame(width: 28, height: 16)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                                .padding(.horizontal, 2)
                                .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 13)
            }
        }
    }

    private func scrollModeButton(_ mode: MouseScrollMode, label: String) -> some View {
        let isSelected = engine.mouseScrollMode == mode
        return Button(action: {
            withAnimation(AppTheme.springSlider) {
                engine.mouseScrollMode = mode
            }
        }) {
            Text(label)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4.5)
                .contentShape(Capsule())
                .background(
                    ZStack {
                        if isSelected {
                            LiquidGlassSlidingPill(accentTint: AppTheme.accent, isDarkNotchStyle: false)
                                .matchedGeometryEffect(id: "ScrollModeLiquidSlider", in: scrollModeSliderNamespace)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Top Header Bar (Selected Profile + Auto-Start Toggle + Accessibility + Save)
    private var topActionBar: some View {
        LiquidGlassCard(cornerRadius: 14, tintColor: AppTheme.accent, isHighlighted: false) {
            HStack(spacing: 12) {
                profileIcon(for: activeProfile)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(activeProfile.appName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(activeProfile.isGlobalDefault ? "Default button rules for all apps" : "Custom button rules for \(activeProfile.appName)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                // Auto-Start & Background Daemon Pill
                LiquidIconButton(
                    icon: engine.runInBackgroundWithoutDock ? "bolt.fill" : "bolt.slash",
                    label: engine.runInBackgroundWithoutDock ? "Auto-Start ON" : "Auto-Start OFF",
                    tint: AppTheme.accent,
                    isActive: engine.runInBackgroundWithoutDock,
                    size: 29,
                    tooltipTitle: engine.runInBackgroundWithoutDock
                        ? "Auto-Start & Background Mode: ON"
                        : "Auto-Start & Background Mode: OFF",
                    tooltipDetail: "Automatically starts MyMouse when you turn on your Mac, and keeps it running even when closed from the Dock."
                ) {
                    withAnimation(AppTheme.springSnappy) {
                        engine.runInBackgroundWithoutDock.toggle()
                    }
                }

                // Accessibility Permission Status Pill
                LiquidIconButton(
                    icon: engine.hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                    label: engine.hasAccessibilityPermission ? "Ready" : "Allow Access",
                    tint: engine.hasAccessibilityPermission ? AppTheme.success : AppTheme.warning,
                    isActive: !engine.hasAccessibilityPermission,
                    size: 29,
                    tooltipTitle: engine.hasAccessibilityPermission
                        ? "Accessibility Permission: Connected"
                        : "Accessibility Permission Needed",
                    tooltipDetail: engine.hasAccessibilityPermission
                        ? "macOS Accessibility is active and controlling your mouse buttons."
                        : "Click to open System Settings → Privacy & Security → Accessibility and enable MyMouse."
                ) {
                    engine.requestAccessibilityPermission()
                }

                // Primary Save Button
                LiquidIconButton(
                    icon: "checkmark",
                    label: engine.saveSuccessPulse ? "Saved" : "Save",
                    tint: engine.saveSuccessPulse ? AppTheme.success : AppTheme.accent,
                    isActive: true,
                    size: 30,
                    tooltipTitle: "Save All Settings",
                    tooltipDetail: "Saves your button shortcuts, app profiles, scroll mode, and pinned items."
                ) {
                    engine.saveAllChanges()
                    ClipboardManager.shared.savePinnedItemsToDisk()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Saved Custom Keys Library Bar
    private var customKeysBar: some View {
        LiquidGlassCard(cornerRadius: 14, tintColor: AppTheme.accent, isHighlighted: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("QUICK SHORTCUTS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                        .tracking(0.6)

                    Text("• Click any shortcut to assign to \(selectedTargetButton.shortName) (\(engine.selectedTapMode.shortLabel))")
                        .font(.system(size: 10.5))
                        .foregroundColor(AppTheme.textSecondary)

                    Spacer()

                    Button(action: { showCreateCustomKeySheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("New Shortcut")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.accentSoft))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            SmartTooltipManager.shared.show(
                                icon: "keyboard",
                                title: "Create Custom Shortcut",
                                detail: "Record any keyboard combination (like ⌘P, ⌃⌥S, F5) and save it here for 1-click assignment.",
                                tint: AppTheme.accent
                            )
                        } else {
                            SmartTooltipManager.shared.hide()
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(engine.savedCustomKeys) { item in
                            let currentMapping = activeProfile.mapping(for: selectedTargetButton, tapCount: engine.selectedTapMode)
                            let isAssigned = currentMapping.actionType == .customShortcut && currentMapping.customCombo == item.combo

                            HStack(spacing: 6) {
                                Button(action: {
                                    let mapping = ButtonMapping(
                                        actionType: .customShortcut,
                                        customCombo: item.combo,
                                        customLabel: item.name
                                    )
                                    withAnimation(AppTheme.springSnappy) {
                                        engine.updateMapping(
                                            for: activeProfile.id,
                                            button: selectedTargetButton,
                                            tapCount: engine.selectedTapMode,
                                            mapping: mapping
                                        )
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Text(item.name)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(isAssigned ? .white : AppTheme.textPrimary)

                                        Text(item.combo.displayString)
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundColor(isAssigned ? .white : AppTheme.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(isAssigned ? Color.white.opacity(0.22) : AppTheme.accentSoft)
                                            )
                                    }
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    withAnimation(AppTheme.springSnappy) {
                                        engine.removeSavedCustomKey(id: item.id)
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(isAssigned ? .white.opacity(0.75) : AppTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isAssigned ? AppTheme.accent : Color.white.opacity(0.05))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(isAssigned ? Color.white.opacity(0.32) : AppTheme.borderSubtle, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func profileIcon(for profile: AppProfile) -> some View {
        if profile.isGlobalDefault {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.accentSoft)
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
            }
        } else if let path = profile.appPath, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.accent)
        }
    }
}

// MARK: - Uniform Sidebar Profile Row (With Gliding Selection Background)
private struct UniformSidebarProfileRow: View {
    let profile: AppProfile
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                icon
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(profile.appName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : AppTheme.textPrimary)
                        .lineLimit(1)

                    Text("\(profile.mapping(for: .sideForward).effectiveBadge)  •  \(profile.mapping(for: .sideBackward).effectiveBadge)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.78) : AppTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if !profile.isGlobalDefault && isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7.5)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "SidebarProfileSelection", in: namespace)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.025))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        if profile.isGlobalDefault {
            Image(systemName: "globe")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(isSelected ? .white : AppTheme.accent)
        } else if let path = profile.appPath, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 13.5))
                .foregroundColor(isSelected ? .white : AppTheme.accent)
        }
    }
}

// MARK: - Uniform Apple-Standard Mouse Button Assignment Row
private struct UniformButtonAssignmentRow: View {
    let buttonKind: MouseButtonKind
    let activeProfile: AppProfile
    let selectedTapMode: TapCountKind
    let savedCustomKeys: [SavedCustomKey]
    let isPressed: Bool
    let isSelected: Bool
    let onSelectRowAndTap: (TapCountKind) -> Void
    let onUpdateMapping: (ButtonMapping) -> Void
    let onRecordKey: () -> Void

    private var mapping: ButtonMapping {
        activeProfile.mapping(for: buttonKind, tapCount: selectedTapMode)
    }

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 13,
            tintColor: AppTheme.accent,
            isHighlighted: isPressed || isSelected
        ) {
            HStack(spacing: 12) {
                // 1. Button Icon + Clean Label
                Button(action: { onSelectRowAndTap(selectedTapMode) }) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isPressed || isSelected ? AppTheme.accent : Color.white.opacity(0.07))
                                .frame(width: 28, height: 28)
                            Image(systemName: buttonKind.iconName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(isPressed || isSelected ? .white : AppTheme.textSecondary)
                        }

                        Text(buttonKind.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(width: 96, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        SmartTooltipManager.shared.show(
                            icon: buttonKind.iconName,
                            title: buttonKind.displayName,
                            detail: buttonKind.tooltipInfo,
                            tint: AppTheme.accent
                        )
                    } else {
                        SmartTooltipManager.shared.hide()
                    }
                }

                // 2. Uniform 1x | 2x | 3x Multi-Tap Status Pills
                HStack(spacing: 5) {
                    ForEach(TapCountKind.allCases) { tap in
                        let tapMap = activeProfile.mapping(for: buttonKind, tapCount: tap)
                        let isActiveTap = isSelected && selectedTapMode == tap
                        Button(action: {
                            onSelectRowAndTap(tap)
                        }) {
                            HStack(spacing: 4) {
                                Text("\(tap.rawValue)×")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(isActiveTap ? .white : AppTheme.accent)
                                Text(tapMap.effectiveBadge)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(isActiveTap ? .white : (tapMap.isConfigured ? AppTheme.textPrimary : AppTheme.textMuted))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isActiveTap ? AppTheme.accent : Color.white.opacity(tapMap.isConfigured ? 0.075 : 0.035))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(isActiveTap ? Color.white.opacity(0.32) : Color.white.opacity(tapMap.isConfigured ? 0.14 : 0.06), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // 3. Action Selector Menu for Selected Tap Count
                Menu {
                    if !savedCustomKeys.isEmpty {
                        Section("Quick Shortcuts (\(selectedTapMode.shortLabel))") {
                            ForEach(savedCustomKeys) { customKey in
                                Button("\(customKey.name) (\(customKey.combo.displayString))") {
                                    onUpdateMapping(ButtonMapping(
                                        actionType: .customShortcut,
                                        customCombo: customKey.combo,
                                        customLabel: customKey.name
                                    ))
                                }
                            }
                        }
                    }

                    Section("Standard Actions (\(selectedTapMode.shortLabel))") {
                        ForEach(ButtonActionType.allCases.filter { $0 != .customShortcut }) { action in
                            Button("\(action.title) (\(action.badgeText))") {
                                onUpdateMapping(ButtonMapping(actionType: action))
                            }
                        }
                    }

                    Divider()

                    Button("Record Custom Key...") {
                        onRecordKey()
                    }
                } label: {
                    HStack {
                        Text("\(selectedTapMode.shortLabel): \(mapping.effectiveTitle)")
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .frame(width: 152)
                }
                .frame(width: 162)

                // 4. Record Custom Key Shortcut Icon Button
                LiquidIconButton(
                    icon: "keyboard",
                    tint: AppTheme.accent,
                    isActive: mapping.actionType == .customShortcut,
                    size: 28,
                    tooltipTitle: "Record Key for \(buttonKind.shortName) (\(selectedTapMode.shortLabel))",
                    tooltipDetail: "Press any custom keyboard shortcut to assign to \(selectedTapMode.fullTitle)."
                ) {
                    onRecordKey()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}
