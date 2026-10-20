# MyMouse Studio (ClickFlow) for macOS

A native **Swift & SwiftUI** macOS utility for customizing external gaming/productivity mouse buttons (**Forward**, **Backward**, **Middle Scroll Wheel**), independent **Windows-style Mouse Wheel Scrolling** (while keeping MacBook Trackpad Natural Scrolling ON), and a **MacBook Camera Notch Dynamic Island Clipboard Manager**.

---

## ✨ Features

1. **Global & Per-Application Mouse Button Profiles**
   - Remap **Forward (Side Button 1)**, **Backward (Side Button 2)**, and **Middle Wheel Click** globally across macOS or create custom rules for specific apps (e.g., Photoshop, Chrome, VS Code, Final Cut Pro).
   - Unassigned apps automatically inherit the **Global (All Apps)** profile.

2. **1× Single, 2× Double & 3× Triple Click Support**
   - Assign up to **3 distinct actions per mouse button** (`1× Single Click`, `2× Double Click`, `3× Triple Click`).
   - Built-in **Quick Shortcuts Library** and live **Keyboard Shortcut Recorder** (`⌘C`, `⌘V`, `⌘P`, `⌃⌥S`, Function keys, etc.).

3. **Independent Mouse Wheel vs. Trackpad Scrolling**
   - **Windows Style:** Reverses external mouse scroll wheel direction to match Windows while keeping MacBook Trackpad **Natural Scrolling ON**.
   - **Mac Default:** Standard macOS scrolling.
   - **Wheel Off:** Disables external mouse wheel scrolling while keeping Middle Click active.

4. **MacBook Camera Notch Dynamic Island Clipboard (`fn + ⌘`)**
   - Anchored directly at the top physical bezel (`screen.frame.maxY`) over the MacBook camera cutout.
   - Morphs smoothly from the physical camera notch in **100% pure pitch-black (`#000000`)** with zero edge outline using `MacBookNotchShape`.
   - Gliding **Liquid Glass Sliding Tab Bar** (`Copied` | `Pinned` | `Images`) with high-DPI Retina screenshot/image previews.
   - **Persistent Pinned Items:** All items in the **Pinned** tab are automatically saved to `~/Library/Application Support/MyMouse/PinnedClipboard/` and survive app restarts, `Clear All`, and Mac shutdown/reboot.

5. **Always-On Background Engine & Auto-Start**
   - Ultra-low CPU/RAM footprint (`0% GPU` when the Studio window is closed).
   - Continues working even when closed and hidden from the Dock (`NSApplication.ActivationPolicy.accessory` + `LaunchAgent` auto-start).

---

## 📁 Project Structure

```text
MyMouse/
├── Sources/
│   ├── Models.swift                  # Data models (Profiles, TapCountKind, ScrollMode, Shortcuts)
│   ├── KeyCodeHelper.swift           # High-priority CGEvent keyboard/action synthesizer
│   ├── LiquidGlassComponents.swift   # Unified AppTheme Design System, LiquidGlassSlidingPill & Tooltip HUD
│   ├── ClipboardManager.swift        # MacBook Notch morphing clipboard & persistent pinned storage
│   ├── MouseEngine.swift             # CGEventTap engine for mouse buttons, scroll wheel & multi-tap
│   ├── InteractiveMouseView.swift    # Live hardware mouse preview & 1x/2x/3x tap switcher
│   ├── ContentView.swift             # Main MyMouse Studio window UI
│   ├── ShortcutRecorderSheet.swift   # Custom keyboard shortcut recorder modal
│   ├── AppPickerSheet.swift          # Installed & running macOS application picker
│   └── MyMouseApp.swift              # AppDelegate, Menu Bar controller & persistent Studio window
├── Resources/
│   └── Info.plist                    # Bundle metadata (macOS 12.0+ Universal)
├── scripts/
│   ├── generate_icon.swift           # Procedural macOS AppIcon generator
│   └── build_dmg.sh                  # Universal Binary (arm64 + x86_64) & DMG build script
└── dist/
    ├── MyMouse.app                   # Built Universal macOS Application Bundle
    ├── MyMouse-Installer.dmg         # Distributable macOS Disk Image Installer
    └── MyMouse.zip                   # Zipped Application Bundle
```

---

## 🛠️ Build & Install

### Option 1: Install from Pre-Built DMG
Open `dist/MyMouse-Installer.dmg` and drag **MyMouse.app** into `/Applications`.

### Option 2: Build Universal Binary & DMG from Source
```bash
./scripts/build_dmg.sh
diskutil image create from --format UDZO --volumeName "MyMouse ClickFlow" ./build/dmg_staging ./dist/MyMouse-Installer.dmg
```

> **Note:** Grant **Accessibility Permission** in **System Settings → Privacy & Security → Accessibility** so `MyMouse` can intercept external mouse buttons and scroll wheel events.
