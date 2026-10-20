import SwiftUI
import AppKit

@main
struct MyMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var studioWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        createStudioWindowIfNeeded()

        // Ensure LaunchAgent for Auto-Start at Login is up to date
        MouseEngine.shared.updateLaunchAgentIfNeeded()

        let launchedInBackground = CommandLine.arguments.contains("--background")
        if launchedInBackground {
            MouseEngine.shared.isStudioWindowVisible = false
            NSApp.setActivationPolicy(.accessory)
            studioWindow?.orderOut(nil)
        } else {
            openMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist all Pinned Clipboard items & Mouse settings before quit / Mac shutdown
        ClipboardManager.shared.savePinnedItemsToDisk()
        MouseEngine.shared.saveAllChanges()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MouseEngine.shared.isStudioWindowVisible = false
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    // Intercept the red Close (X) button so the window is never destroyed — just hidden to Menu Bar!
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MouseEngine.shared.isStudioWindowVisible = false
        ClipboardManager.shared.savePinnedItemsToDisk()
        sender.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    private func createStudioWindowIfNeeded() {
        guard studioWindow == nil else { return }

        let contentView = ContentView(engine: MouseEngine.shared)
            .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 595),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "My Mouse"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 840, height: 575)
        window.contentView = hostingView
        window.delegate = self
        window.center()

        self.studioWindow = window
        MouseEngine.shared.studioWindowRef = window
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "My Mouse")
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open My Mouse...", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let clipItem = NSMenuItem(title: "Clipboard (fn + ⌘)", action: #selector(openClipboardPopup), keyEquivalent: "v")
        clipItem.target = self
        menu.addItem(clipItem)

        menu.addItem(NSMenuItem.separator())

        let hideDockItem = NSMenuItem(title: "Close Window & Hide from Dock", action: #selector(hideFromDock), keyEquivalent: "h")
        hideDockItem.target = self
        menu.addItem(hideDockItem)

        let toggleItem = NSMenuItem(title: "Pause / Resume Mouse Engine", action: #selector(toggleEngine), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit My Mouse", action: #selector(quitAppCompletely), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    @objc func openMainWindow() {
        createStudioWindowIfNeeded()
        MouseEngine.shared.isStudioWindowVisible = true

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let win = self.studioWindow else { return }
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func hideFromDock() {
        MouseEngine.shared.isStudioWindowVisible = false
        ClipboardManager.shared.savePinnedItemsToDisk()
        studioWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openClipboardPopup() {
        ClipboardManager.shared.togglePopup()
    }

    @objc private func toggleEngine() {
        MouseEngine.shared.isEngineEnabled.toggle()
    }

    @objc private func quitAppCompletely() {
        // Save Pinned Clipboard items & settings before quitting; keep LaunchAgent if Auto-Start is ON
        ClipboardManager.shared.savePinnedItemsToDisk()
        MouseEngine.shared.saveAllChanges()
        MouseEngine.shared.updateLaunchAgentIfNeeded()
        NSApp.terminate(nil)
    }
}
