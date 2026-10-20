import SwiftUI
import AppKit
import ImageIO
import Carbon.HIToolbox

// MARK: - MacBook Hardware Notch Morphing Shape (Concave Top Ears + Rounded Bottom)
/// Draws a single continuous shape anchored at the very top bezel (`y = 0`):
/// - Top-left and top-right corners flare *outward* with concave quadratic curves (`topCornerRadius`)
///   so the vertical walls blend tangentially into the physical MacBook top bezel.
/// - Bottom-left and bottom-right corners curve *inward* with smooth rounded corners (`bottomCornerRadius`).
/// - Conforms to `Animatable` across all 4 parameters (`width`, `height`, `topCornerRadius`, `bottomCornerRadius`)
///   so SwiftUI interpolates the entire silhouette at 120Hz with zero layout jitter.
struct MacBookNotchShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(width, height),
                AnimatablePair(topCornerRadius, bottomCornerRadius)
            )
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            topCornerRadius = newValue.second.first
            bottomCornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = max(32, min(width, rect.width))
        let h = max(12, min(height, rect.height))
        let minX = rect.midX - (w / 2.0)
        let maxX = rect.midX + (w / 2.0)
        let minY: CGFloat = 0 // Always 100% flush with the physical top screen edge!
        let maxY = h

        let topR = max(0, min(topCornerRadius, w / 4.0, h / 2.0))
        let innerWidth = max(0, w - (2.0 * topR))
        let bottomR = max(0, min(bottomCornerRadius, innerWidth / 2.0, h - topR))

        // 1. Start at top-left tip flush with the physical top screen edge (y = 0)
        path.move(to: CGPoint(x: minX, y: minY))

        // 2. Top horizontal edge across the camera notch
        path.addLine(to: CGPoint(x: maxX, y: minY))

        // 3. Top-right concave "notch ear" curving smoothly down into the right vertical wall
        path.addQuadCurve(
            to: CGPoint(x: maxX - topR, y: minY + topR),
            control: CGPoint(x: maxX - topR, y: minY)
        )

        // 4. Right vertical wall down to bottom-right corner
        path.addLine(to: CGPoint(x: maxX - topR, y: maxY - bottomR))

        // 5. Bottom-right convex rounded corner
        path.addQuadCurve(
            to: CGPoint(x: maxX - topR - bottomR, y: maxY),
            control: CGPoint(x: maxX - topR, y: maxY)
        )

        // 6. Bottom horizontal edge
        path.addLine(to: CGPoint(x: minX + topR + bottomR, y: maxY))

        // 7. Bottom-left convex rounded corner
        path.addQuadCurve(
            to: CGPoint(x: minX + topR, y: maxY - bottomR),
            control: CGPoint(x: minX + topR, y: maxY)
        )

        // 8. Left vertical wall up to top-left concave "notch ear"
        path.addLine(to: CGPoint(x: minX + topR, y: minY + topR))

        // 9. Top-left concave "notch ear" flaring smoothly out to the top screen edge (y = 0)
        path.addQuadCurve(
            to: CGPoint(x: minX, y: minY),
            control: CGPoint(x: minX + topR, y: minY)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Clipboard Item Model
struct ClipboardEntry: Identifiable, Equatable {
    enum ContentKind: Equatable {
        case text(String)
        case image(Data, CGSize)
    }

    let id: UUID
    let timestamp: Date
    let kind: ContentKind
    var isPinned: Bool
    var previewImage: NSImage?

    var isImage: Bool {
        if case .image = kind { return true }
        return false
    }

    var textPreview: String {
        switch kind {
        case .text(let str):
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image(_, let size):
            return "PNG Image • \(Int(size.width)) × \(Int(size.height))"
        }
    }

    var metadataLabel: String {
        switch kind {
        case .text(let str):
            let count = str.trimmingCharacters(in: .whitespacesAndNewlines).count
            return "\(count) chars"
        case .image(_, let size):
            return "\(Int(size.width))×\(Int(size.height)) px"
        }
    }

    var relativeTimeString: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(timestamp)))
        if elapsed < 45 { return "Just now" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        if elapsed < 86400 { return "\(elapsed / 3600)h ago" }
        return "\(elapsed / 86400)d ago"
    }

    static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
        lhs.id == rhs.id && lhs.isPinned == rhs.isPinned
    }
}

// MARK: - On-Disk Codable Record for Pinned Items (Survives App Quit & Mac Shutdown)
private struct PersistedPinnedRecord: Codable {
    let id: UUID
    let timestamp: Date
    let isImage: Bool
    let textContent: String?
    let imageFileName: String?
    let imageWidth: Double?
    let imageHeight: Double?
}

// MARK: - Dynamic Island Clipboard Manager & Controller
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledStorageKey)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
                closePopup()
            }
        }
    }

    @Published var hotkeyMode: ClipboardHotkeyMode = .fnCommand {
        didSet {
            UserDefaults.standard.set(hotkeyMode.rawValue, forKey: hotkeyStorageKey)
        }
    }

    @Published var items: [ClipboardEntry] = []
    @Published var selectedTab: FilterTab = .copied
    @Published var showClearAllConfirmation: Bool = false

    // Dynamic Island visual state & detected physical MacBook notch size
    @Published var islandMode: IslandMode = .hidden
    @Published var latestToastEntry: ClipboardEntry? = nil
    @Published var notchSize: CGSize = CGSize(width: 188, height: 32)

    // Fixed borderless canvas dimensions (top-anchored at screen.frame.maxY)
    static let panelCanvasWidth: CGFloat = 540
    static let panelCanvasHeight: CGFloat = 480

    enum IslandMode: Equatable {
        case hidden
        case compactToast
        case expandedDrawer
    }

    enum FilterTab: String, CaseIterable, Identifiable {
        case copied = "Copied"
        case pinned = "Pinned"
        case images = "Images"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .copied: return "doc.on.clipboard"
            case .pinned: return "pin.fill"
            case .images: return "photo"
            }
        }
    }

    private var pollTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var desktopWatcher: DispatchSourceFileSystemObject?
    private var desktopFD: Int32 = -1
    private var knownDesktopFiles: Set<String> = []
    private var popupPanel: DynamicIslandPanel?
    private var hostingView: NotchPassthroughHostingView<DynamicIslandClipboardView>?
    private var previousApp: NSRunningApplication?
    private var workspaceAppObserver: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var outsideClickMonitor: Any?
    private var screenChangeObserver: Any?
    private var terminationObserver: Any?
    private var toastDismissWorkItem: DispatchWorkItem?
    private var hideOrderOutWorkItem: DispatchWorkItem?
    private var lastHotkeyTriggerTime: TimeInterval = 0
    private var isInternalPaste: Bool = false

    private let enabledStorageKey = "MyMouse.Clipboard.Enabled.v3"
    private let hotkeyStorageKey = "MyMouse.Clipboard.Hotkey.v3"
    private let maxUnpinnedItems = 35

    private var pinnedStorageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support"))
        return appSupport
            .appendingPathComponent("MyMouse", isDirectory: true)
            .appendingPathComponent("PinnedClipboard", isDirectory: true)
    }

    private var pinnedManifestURL: URL {
        pinnedStorageDirectory.appendingPathComponent("pinned_items_v1.json")
    }

    private init() {
        if UserDefaults.standard.object(forKey: enabledStorageKey) != nil {
            isEnabled = UserDefaults.standard.bool(forKey: enabledStorageKey)
        }
        if let savedHotkey = UserDefaults.standard.string(forKey: hotkeyStorageKey),
           let mode = ClipboardHotkeyMode(rawValue: savedHotkey) {
            hotkeyMode = mode
        }

        // Restore all Pinned items from disk immediately on launch / reboot!
        loadPinnedItemsFromDisk()

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        workspaceAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return
            }
            self.previousApp = app
        }

        setupGlobalHotkeyMonitors()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.popupPanel?.isVisible == true else { return }
            self.positionPanelAtTopCenter()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.savePinnedItemsToDisk()
        }

        if isEnabled {
            startMonitoring()
        }
    }

    // MARK: - Persistent Storage for Pinned Items (Survives Shutdown / Quit / Restart)
    func savePinnedItemsToDisk() {
        let pinnedEntries = items.filter { $0.isPinned }
        let dir = pinnedStorageDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var records: [PersistedPinnedRecord] = []
        var activeImageFiles: Set<String> = []

        for entry in pinnedEntries {
            switch entry.kind {
            case .text(let str):
                records.append(PersistedPinnedRecord(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    isImage: false,
                    textContent: str,
                    imageFileName: nil,
                    imageWidth: nil,
                    imageHeight: nil
                ))
            case .image(let pngData, let size):
                let fileName = "\(entry.id.uuidString).png"
                let fileURL = dir.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    try? pngData.write(to: fileURL, options: .atomic)
                }
                activeImageFiles.insert(fileName)
                records.append(PersistedPinnedRecord(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    isImage: true,
                    textContent: nil,
                    imageFileName: fileName,
                    imageWidth: Double(size.width),
                    imageHeight: Double(size.height)
                ))
            }
        }

        if let jsonData = try? JSONEncoder().encode(records) {
            try? jsonData.write(to: pinnedManifestURL, options: .atomic)
        }

        // Clean up any unpinned/deleted image files on disk
        if let existingFiles = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for file in existingFiles where file.hasSuffix(".png") && !activeImageFiles.contains(file) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    private func loadPinnedItemsFromDisk() {
        guard let data = try? Data(contentsOf: pinnedManifestURL),
              let records = try? JSONDecoder().decode([PersistedPinnedRecord].self, from: data) else {
            return
        }

        let dir = pinnedStorageDirectory
        var restored: [ClipboardEntry] = []

        for rec in records {
            if rec.isImage, let fileName = rec.imageFileName {
                let fileURL = dir.appendingPathComponent(fileName)
                if let pngData = try? Data(contentsOf: fileURL) {
                    let size = CGSize(width: rec.imageWidth ?? 800, height: rec.imageHeight ?? 600)
                    let thumb = Self.createRetinaThumbnail(from: pngData, maxPixelDimension: 640)
                    restored.append(ClipboardEntry(
                        id: rec.id,
                        timestamp: rec.timestamp,
                        kind: .image(pngData, size),
                        isPinned: true,
                        previewImage: thumb
                    ))
                }
            } else if let text = rec.textContent, !text.isEmpty {
                restored.append(ClipboardEntry(
                    id: rec.id,
                    timestamp: rec.timestamp,
                    kind: .text(text),
                    isPinned: true,
                    previewImage: nil
                ))
            }
        }

        if !restored.isEmpty {
            self.items = restored
        }
    }

    // MARK: - Global Hotkey Monitor (Also called from MouseEngine CGEventTap for 100% reliability)
    private func setupGlobalHotkeyMonitors() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleHotkeyEvent(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event
        }
    }

    func handleCGFlagsChanged(_ flags: CGEventFlags) {
        guard isEnabled, hotkeyMode == .fnCommand else { return }
        if flags.contains(.maskSecondaryFn) && flags.contains(.maskCommand) &&
           !flags.contains(.maskShift) && !flags.contains(.maskAlternate) && !flags.contains(.maskControl) {
            triggerPopupWithCooldown()
        }
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        let flags = event.modifierFlags

        if event.type == .flagsChanged && hotkeyMode == .fnCommand {
            if flags.contains(.function) && flags.contains(.command) &&
               !flags.contains(.shift) && !flags.contains(.option) && !flags.contains(.control) {
                triggerPopupWithCooldown()
            }
        } else if event.type == .keyDown {
            let cleanFlags = flags.intersection([.command, .shift, .option, .control])
            if event.keyCode == UInt16(kVK_ANSI_V) {
                if hotkeyMode == .optionV && cleanFlags == [.option] {
                    triggerPopupWithCooldown()
                } else if hotkeyMode == .cmdShiftV && cleanFlags == [.command, .shift] {
                    triggerPopupWithCooldown()
                }
            }
        }
    }

    func triggerPopupWithCooldown() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHotkeyTriggerTime > 0.35 else { return }
        lastHotkeyTriggerTime = now
        DispatchQueue.main.async {
            self.togglePopup()
        }
    }

    // MARK: - Start / Stop Low-Power Monitoring
    func startMonitoring() {
        stopMonitoring()
        guard isEnabled else { return }

        lastChangeCount = NSPasteboard.general.changeCount

        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer

        setupScreenshotFolderWatcher()
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil

        desktopWatcher?.cancel()
        desktopWatcher = nil
        if desktopFD != -1 {
            close(desktopFD)
            desktopFD = -1
        }
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if isInternalPaste {
            isInternalPaste = false
            return
        }

        // 1. Check Image / Screenshot data on Pasteboard
        if let imgData = pb.data(forType: .png) ?? pb.data(forType: .tiff),
           let nsImage = NSImage(data: imgData) {
            addImageEntry(nsImage)
            return
        }

        // 2. Check Image file URL copied in Finder
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            let ext = firstURL.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"].contains(ext),
               let nsImage = NSImage(contentsOf: firstURL) {
                addImageEntry(nsImage)
                return
            }
        }

        // 3. Check Copied Text
        if let str = pb.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            addTextEntry(str)
        }
    }

    private func setupScreenshotFolderWatcher() {
        let desktopPath = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? (NSHomeDirectory() + "/Desktop")
        if let existing = try? FileManager.default.contentsOfDirectory(atPath: desktopPath) {
            knownDesktopFiles = Set(existing)
        }

        desktopFD = open(desktopPath, O_EVTONLY)
        guard desktopFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: desktopFD,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.checkForNewScreenshots(in: desktopPath)
        }
        source.resume()
        self.desktopWatcher = source
    }

    private func checkForNewScreenshots(in folderPath: String) {
        guard let currentFiles = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else { return }
        let currentSet = Set(currentFiles)
        let added = currentSet.subtracting(knownDesktopFiles)
        knownDesktopFiles = currentSet

        for fileName in added {
            let lower = fileName.lowercased()
            guard !fileName.hasPrefix("."),
                  (lower.contains("screen shot") || lower.contains("screenshot") || lower.contains("cleanshot")),
                  (lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")) else {
                continue
            }
            let fullPath = (folderPath as NSString).appendingPathComponent(fileName)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                if let img = NSImage(contentsOfFile: fullPath) {
                    self?.addImageEntry(img)
                }
            }
        }
    }

    // MARK: - High-DPI Retina Thumbnail Generator (True Aspect Ratio, Ultra-Low RAM)
    private static func createRetinaThumbnail(from pngData: Data, maxPixelDimension: Int = 600) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: pngData)
        }
        let pointSize = NSSize(width: CGFloat(cgThumb.width) / 2.0, height: CGFloat(cgThumb.height) / 2.0)
        return NSImage(cgImage: cgThumb, size: pointSize)
    }

    // MARK: - Add / Manage Entries
    func addTextEntry(_ text: String) {
        if let existingIdx = items.firstIndex(where: {
            if case .text(let t) = $0.kind { return t == text }
            return false
        }) {
            let existing = items.remove(at: existingIdx)
            let updated = ClipboardEntry(
                id: existing.id,
                timestamp: Date(),
                kind: .text(text),
                isPinned: existing.isPinned,
                previewImage: nil
            )
            items.insert(updated, at: 0)
            if updated.isPinned {
                savePinnedItemsToDisk()
            }
            showCompactDynamicIslandToast(for: updated)
            return
        }

        let entry = ClipboardEntry(
            id: UUID(),
            timestamp: Date(),
            kind: .text(text),
            isPinned: false,
            previewImage: nil
        )
        items.insert(entry, at: 0)
        trimHistoryIfNeeded()
        showCompactDynamicIslandToast(for: entry)
    }

    func addImageEntry(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }

        let pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        guard pixelSize.width > 1 && pixelSize.height > 1 else { return }

        let crispThumb = Self.createRetinaThumbnail(from: pngData, maxPixelDimension: 640)

        let entry = ClipboardEntry(
            id: UUID(),
            timestamp: Date(),
            kind: .image(pngData, pixelSize),
            isPinned: false,
            previewImage: crispThumb
        )
        items.insert(entry, at: 0)
        trimHistoryIfNeeded()
        showCompactDynamicIslandToast(for: entry)
    }

    private func trimHistoryIfNeeded() {
        let unpinnedCount = items.filter { !$0.isPinned }.count
        if unpinnedCount > maxUnpinnedItems {
            if let lastUnpinnedIdx = items.lastIndex(where: { !$0.isPinned }) {
                items.remove(at: lastUnpinnedIdx)
            }
        }
    }

    /// Moves item between Copied/Images and the dedicated Pinned tab, and persists Pinned items to disk!
    func togglePin(_ entry: ClipboardEntry) {
        guard let idx = items.firstIndex(where: { $0.id == entry.id }) else { return }
        withAnimation(AppTheme.springSlider) {
            items[idx].isPinned.toggle()
        }
        savePinnedItemsToDisk()
    }

    func deleteEntry(_ entry: ClipboardEntry) {
        let wasPinned = entry.isPinned
        withAnimation(AppTheme.springSnappy) {
            items.removeAll { $0.id == entry.id }
        }
        if wasPinned {
            savePinnedItemsToDisk()
        }
    }

    /// Clears ONLY unpinned items — Pinned items remain 100% intact on disk and in the Pinned tab!
    func clearAllUnpinned() {
        withAnimation(AppTheme.springSlider) {
            items.removeAll { !$0.isPinned }
            showClearAllConfirmation = false
        }
        savePinnedItemsToDisk()
    }

    // MARK: - Paste Selected Item Directly into Active Placeholder / Cursor
    func pasteItem(_ entry: ClipboardEntry) {
        isInternalPaste = true
        let pb = NSPasteboard.general
        pb.clearContents()

        switch entry.kind {
        case .text(let str):
            pb.setString(str, forType: .string)
        case .image(let pngData, _):
            pb.setData(pngData, forType: .png)
            if let img = NSImage(data: pngData), let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
        lastChangeCount = pb.changeCount

        // Determine the external app where the user's cursor / placeholder is waiting
        let currentFront = NSWorkspace.shared.frontmostApplication
        let targetApp: NSRunningApplication?
        if let front = currentFront, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        } else {
            targetApp = previousApp
        }

        toastDismissWorkItem?.cancel()
        hideOrderOutWorkItem?.cancel()
        removeOutsideClickMonitor()
        showClearAllConfirmation = false
        popupPanel?.ignoresMouseEvents = true
        popupPanel?.resignKey()

        // Snappy notch collapse so the panel is 100% ordered out before ⌘V is sent
        withAnimation(.spring(response: 0.20, dampingFraction: 0.88, blendDuration: 0.08)) {
            islandMode = .hidden
        }

        let orderOutAndPasteWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.islandMode == .hidden {
                self.popupPanel?.orderOut(nil)
            }

            if !AXIsProcessTrusted() {
                MouseEngine.shared.requestAccessibilityPermission()
                return
            }

            if let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
                app.activate(options: [.activateIgnoringOtherApps])
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                KeyCodeHelper.sendKeyCombo(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
            }
        }
        hideOrderOutWorkItem = orderOutAndPasteWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: orderOutAndPasteWork)
    }

    // MARK: - Hardware MacBook Notch Geometry Detection & Window Management
    private func detectHardwareNotchSize(for screen: NSScreen?) -> CGSize {
        guard let screen = screen else {
            return CGSize(width: 188, height: 32)
        }
        let safeTop = screen.safeAreaInsets.top
        if safeTop > 0 {
            let leftAux = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightAux = screen.auxiliaryTopRightArea?.width ?? 0
            let rawNotchWidth = screen.frame.width - leftAux - rightAux
            let validWidth = (rawNotchWidth >= 110 && rawNotchWidth <= 340) ? rawNotchWidth : 188
            return CGSize(width: validWidth, height: max(safeTop, 32))
        }
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 30)
        return CGSize(width: 188, height: min(max(menuBarHeight, 30), 37))
    }

    func activeMorphSize(for mode: IslandMode) -> CGSize {
        switch mode {
        case .hidden:
            return CGSize(width: notchSize.width + 12, height: notchSize.height)
        case .compactToast:
            return CGSize(width: 430, height: notchSize.height + 52)
        case .expandedDrawer:
            return CGSize(width: 510, height: 454)
        }
    }

    private func ensurePanelCreated() {
        guard popupPanel == nil else { return }
        let panel = DynamicIslandPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.panelCanvasWidth,
                height: Self.panelCanvasHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        let host = NotchPassthroughHostingView(
            rootView: DynamicIslandClipboardView(manager: self),
            manager: self
        )
        panel.contentView = host
        self.hostingView = host
        self.popupPanel = panel
    }

    private func positionPanelAtTopCenter() {
        guard let panel = popupPanel else { return }
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main
        let fullFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let detected = detectHardwareNotchSize(for: screen)
        if notchSize != detected {
            notchSize = detected
        }

        let pw = Self.panelCanvasWidth
        let ph = Self.panelCanvasHeight
        let px = fullFrame.midX - (pw / 2.0)
        // Flush with the very top physical pixel row of the MacBook screen (`fullFrame.maxY`)
        let py = fullFrame.maxY - ph

        panel.setFrame(NSRect(x: px, y: py, width: pw, height: ph), display: true)
    }

    /// Briefly morphs the MacBook camera notch into a sleek deep-black compact Island when user copies something new
    private func showCompactDynamicIslandToast(for entry: ClipboardEntry) {
        guard isEnabled else { return }
        if islandMode == .expandedDrawer && popupPanel?.isVisible == true {
            return
        }

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        hideOrderOutWorkItem?.cancel()
        toastDismissWorkItem?.cancel()

        ensurePanelCreated()
        positionPanelAtTopCenter()
        popupPanel?.ignoresMouseEvents = false
        latestToastEntry = entry

        let wasHidden = (popupPanel?.isVisible != true) || (islandMode == .hidden)
        if wasHidden {
            islandMode = .hidden
            popupPanel?.orderFrontRegardless()
            hostingView?.layoutSubtreeIfNeeded()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(AppTheme.springNotchExpand) {
                self.islandMode = .compactToast
            }
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.islandMode == .compactToast else { return }
            withAnimation(AppTheme.springNotchCollapse) {
                self.islandMode = .hidden
            }
            let orderOutWork = DispatchWorkItem { [weak self] in
                if self?.islandMode == .hidden {
                    self?.popupPanel?.orderOut(nil)
                }
            }
            self.hideOrderOutWorkItem = orderOutWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: orderOutWork)
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1, execute: work)
    }

    func togglePopup() {
        guard isEnabled else { return }
        if islandMode == .expandedDrawer && popupPanel?.isVisible == true {
            closePopup()
        } else {
            showPopup()
        }
    }

    func showPopup() {
        guard isEnabled else { return }
        hideOrderOutWorkItem?.cancel()
        toastDismissWorkItem?.cancel()
        showClearAllConfirmation = false

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        ensurePanelCreated()
        positionPanelAtTopCenter()
        popupPanel?.ignoresMouseEvents = false

        let wasVisible = (popupPanel?.isVisible == true) && (islandMode != .hidden)
        if !wasVisible {
            islandMode = .hidden
            popupPanel?.orderFrontRegardless()
            hostingView?.layoutSubtreeIfNeeded()
        } else {
            popupPanel?.orderFrontRegardless()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(AppTheme.springNotchExpand) {
                self.islandMode = .expandedDrawer
            }
        }

        installOutsideClickMonitor()
    }

    func closePopup() {
        toastDismissWorkItem?.cancel()
        hideOrderOutWorkItem?.cancel()
        removeOutsideClickMonitor()
        showClearAllConfirmation = false
        popupPanel?.ignoresMouseEvents = true
        popupPanel?.resignKey()

        withAnimation(AppTheme.springNotchCollapse) {
            islandMode = .hidden
        }

        let orderOutWork = DispatchWorkItem { [weak self] in
            if self?.islandMode == .hidden {
                self?.popupPanel?.orderOut(nil)
            }
        }
        hideOrderOutWorkItem = orderOutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: orderOutWork)
    }

    func activeNotchScreenRect() -> NSRect {
        guard let panel = popupPanel else { return .zero }
        let size = activeMorphSize(for: islandMode)
        let pf = panel.frame
        return NSRect(
            x: pf.midX - (size.width / 2.0),
            y: pf.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.popupPanel, panel.isVisible else { return }
            let mouseLoc = NSEvent.mouseLocation
            if !NSPointInRect(mouseLoc, self.activeNotchScreenRect()) {
                DispatchQueue.main.async {
                    self.closePopup()
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let mon = outsideClickMonitor {
            NSEvent.removeMonitor(mon)
            outsideClickMonitor = nil
        }
    }
}

// MARK: - Top-Bezel Unconstrained Non-Activating Panel & Passthrough Hosting View
private final class DynamicIslandPanel: NSPanel {
    // CRITICAL: Must return false so opening or clicking inside the Notch Clipboard
    // NEVER steals key focus away from the user's active text field / cursor placeholder!
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // CRITICAL: Prevent AppKit from clamping the window below the macOS menu bar / physical notch!
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        ClipboardManager.shared.closePopup()
    }
}

private final class NotchPassthroughHostingView<Content: View>: NSHostingView<Content> {
    weak var manager: ClipboardManager?

    init(rootView: Content, manager: ClipboardManager) {
        self.manager = manager
        super.init(rootView: rootView)
    }

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // CRITICAL: Accept first-mouse clicks immediately without requiring the panel to become key!
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let manager = manager, manager.islandMode != .hidden else {
            return nil
        }
        let activeSize = manager.activeMorphSize(for: manager.islandMode)
        let activeRect = NSRect(
            x: bounds.midX - (activeSize.width / 2.0),
            y: bounds.maxY - activeSize.height,
            width: activeSize.width,
            height: activeSize.height
        )
        guard NSPointInRect(point, activeRect) else {
            return nil
        }
        return super.hitTest(point)
    }
}

// MARK: - True MacBook Notch Morphing Clipboard View (Pure Pitch-Black, Liquid Glass Slider, SF Pro UI)
struct DynamicIslandClipboardView: View {
    @ObservedObject var manager: ClipboardManager
    @Namespace private var tabSliderNamespace

    // Strictly separated lists! Pinned items ONLY appear in Pinned tab!
    private var unpinnedCopiedTextItems: [ClipboardEntry] {
        manager.items.filter { !$0.isPinned && !$0.isImage }
    }

    private var pinnedOnlyItems: [ClipboardEntry] {
        manager.items.filter { $0.isPinned }
    }

    private var imageOnlyItems: [ClipboardEntry] {
        manager.items.filter { !$0.isPinned && $0.isImage }
    }

    private var activeTabItems: [ClipboardEntry] {
        switch manager.selectedTab {
        case .copied: return unpinnedCopiedTextItems
        case .pinned: return pinnedOnlyItems
        case .images: return imageOnlyItems
        }
    }

    private var unpinnedTotalCount: Int {
        manager.items.filter { !$0.isPinned }.count
    }

    private var currentMorphSize: CGSize {
        manager.activeMorphSize(for: manager.islandMode)
    }

    private var currentTopCornerRadius: CGFloat {
        switch manager.islandMode {
        case .hidden: return 6
        case .compactToast: return 14
        case .expandedDrawer: return 18
        }
    }

    private var currentBottomCornerRadius: CGFloat {
        switch manager.islandMode {
        case .hidden: return 10
        case .compactToast: return 22
        case .expandedDrawer: return 28
        }
    }

    var body: some View {
        let size = currentMorphSize
        let topR = currentTopCornerRadius
        let bottomR = currentBottomCornerRadius
        let notchHeight = manager.notchSize.height
        let morphShape = MacBookNotchShape(
            width: size.width,
            height: size.height,
            topCornerRadius: topR,
            bottomCornerRadius: bottomR
        )

        ZStack(alignment: .top) {
            // 1. Pure pitch-black (#000000) hardware notch fill — ZERO border or outline on the edges!
            morphShape
                .fill(Color.black)
                .shadow(
                    color: manager.islandMode == .hidden ? Color.clear : Color.black.opacity(0.62),
                    radius: manager.islandMode == .expandedDrawer ? 24 : 14,
                    x: 0,
                    y: manager.islandMode == .expandedDrawer ? 12 : 6
                )

            // 2. Content inside the morphing pitch-black notch (masked by the exact same Animatable shape!)
            ZStack(alignment: .top) {
                if manager.islandMode == .compactToast {
                    compactToastContent(notchHeight: notchHeight)
                        .padding(.horizontal, 14)
                        .frame(width: 430, height: notchHeight + 52, alignment: .top)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.88, anchor: .top))
                        )
                } else if manager.islandMode == .expandedDrawer {
                    expandedNotchDrawerContent(notchHeight: notchHeight)
                        .padding(.horizontal, 18)
                        .frame(width: 510, height: 454, alignment: .top)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.88, anchor: .top))
                        )
                }
            }
            .frame(
                width: ClipboardManager.panelCanvasWidth,
                height: ClipboardManager.panelCanvasHeight,
                alignment: .top
            )
            .clipShape(morphShape)
        }
        .frame(
            width: ClipboardManager.panelCanvasWidth,
            height: ClipboardManager.panelCanvasHeight,
            alignment: .top
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - 1. Compact Notch Morph Toast (On Copy / Screenshot)
    private func compactToastContent(notchHeight: CGFloat) -> some View {
        Button(action: {
            manager.showPopup()
        }) {
            VStack(spacing: 0) {
                // Top Notch Wing Row (Flanking the physical MacBook camera in the center)
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(manager.latestToastEntry?.isImage == true ? "Screenshot" : "Clipboard")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    .padding(.leading, 12)

                    Spacer(minLength: 0)

                    // Center physical camera cutout keep-out zone
                    Color.clear
                        .frame(width: manager.notchSize.width, height: notchHeight)

                    Spacer(minLength: 0)

                    Text("fn + ⌘")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .padding(.trailing, 12)
                }
                .frame(height: notchHeight)

                // Lower Morph Area directly below the physical camera cutout
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.18))
                            .frame(width: 28, height: 28)
                        Image(systemName: manager.latestToastEntry?.isImage == true ? "photo" : "checkmark")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(manager.latestToastEntry?.isImage == true ? "Image Saved to Notch" : "Copied to Notch")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        if let entry = manager.latestToastEntry {
                            Text(entry.textPreview)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)

                    if let thumb = manager.latestToastEntry?.previewImage {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Text("Open")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Expanded Deep-Black Notch Clipboard Drawer (fn + Command)
    private func expandedNotchDrawerContent(notchHeight: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 11) {
                // Top Notch Ear Wings (Flanking the physical MacBook camera at y = 0 ..< notchHeight)
                HStack(spacing: 0) {
                    // Left Wing: Sleek Close Pill
                    HStack(spacing: 8) {
                        Button(action: { manager.closePopup() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(AppTheme.textSecondary)
                                Text("Close")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 14)

                    // Center Physical MacBook Camera Cutout Zone (Pure Pitch Black)
                    Color.clear
                        .frame(width: manager.notchSize.width, height: notchHeight)

                    // Right Wing: Clear All Button (Clears unpinned items only; Pinned items stay safe!)
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)

                        if unpinnedTotalCount > 0 {
                            Button(action: {
                                withAnimation(AppTheme.springSnappy) {
                                    manager.showClearAllConfirmation = true
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Text("Clear All")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(AppTheme.danger)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(AppTheme.danger.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("fn + ⌘")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Capsule().fill(Color.white.opacity(0.05)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 14)
                }
                .frame(height: max(notchHeight, 32))
                .padding(.top, 2)

                // MARK: Single Gliding Liquid Glass Sliding Tab Bar (Copied | Pinned | Images)
                HStack(spacing: 0) {
                    slidingTabButton(.copied, count: unpinnedCopiedTextItems.count)
                    slidingTabButton(.pinned, count: pinnedOnlyItems.count)
                    slidingTabButton(.images, count: imageOnlyItems.count)
                }
                .padding(3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.055))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)

                // Items Scroll Area inside the pitch-black notch
                if activeTabItems.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 46, height: 46)
                            Image(systemName: emptyStateIcon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        Text(emptyStateTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(emptyStateSubtitle)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(AppTheme.textMuted)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 7) {
                            ForEach(activeTabItems) { item in
                                DynamicIslandItemCard(
                                    item: item,
                                    onPaste: { manager.pasteItem(item) },
                                    onTogglePin: { manager.togglePin(item) },
                                    onDelete: { manager.deleteEntry(item) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .id(manager.selectedTab)
                    .transition(.opacity)
                }
            }
            .blur(radius: manager.showClearAllConfirmation ? 5 : 0)

            // Clear All Confirmation Modal Overlay inside the Notch
            if manager.showClearAllConfirmation {
                Color.black.opacity(0.72)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            manager.showClearAllConfirmation = false
                        }
                    }

                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.danger.opacity(0.16))
                            .frame(width: 38, height: 38)
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.danger)
                    }

                    Text("Clear Copied History?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    Text("Removes \(unpinnedTotalCount) unpinned item(s).\nAll \(pinnedOnlyItems.count) Pinned item(s) are safely preserved.")
                        .font(.system(size: 11.5))
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                manager.showClearAllConfirmation = false
                            }
                        }) {
                            Text("Cancel")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7.5)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            manager.clearAllUnpinned()
                        }) {
                            Text("Clear Unpinned")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7.5)
                                .background(Capsule().fill(AppTheme.danger))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(width: 296)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(white: 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.75), radius: 22, x: 0, y: 8)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
    }

    // MARK: - Single Liquid Glass Sliding Tab Button (`matchedGeometryEffect`)
    private func slidingTabButton(_ tab: ClipboardManager.FilterTab, count: Int) -> some View {
        let isSelected = manager.selectedTab == tab
        return Button(action: {
            withAnimation(AppTheme.springSlider) {
                manager.selectedTab = tab
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : AppTheme.textSecondary)

                Text(tab.rawValue)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : AppTheme.textSecondary)

                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : AppTheme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isSelected ? 0.18 : 0.06))
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6.5)
            .contentShape(Capsule())
            .background(
                ZStack {
                    if isSelected {
                        LiquidGlassSlidingPill(accentTint: AppTheme.accent, isDarkNotchStyle: true)
                            .matchedGeometryEffect(id: "NotchTabLiquidGlassSlider", in: tabSliderNamespace)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyStateIcon: String {
        switch manager.selectedTab {
        case .copied: return "doc.on.clipboard"
        case .pinned: return "pin"
        case .images: return "photo.on.rectangle"
        }
    }

    private var emptyStateTitle: String {
        switch manager.selectedTab {
        case .copied: return "No Copied Text Yet"
        case .pinned: return "No Pinned Items"
        case .images: return "No Screenshots or Images"
        }
    }

    private var emptyStateSubtitle: String {
        switch manager.selectedTab {
        case .copied: return "Press ⌘C anywhere to capture text.\nPinned items are stored in the Pinned tab."
        case .pinned: return "Pin important snippets or images here.\nPinned items stay saved even after shutting down your Mac."
        case .images: return "Copy an image or take a screenshot (⇧⌘4)\nto view and paste it from here."
        }
    }
}

// MARK: - Refined Apple-Standard Item Card Inside MacBook Notch Island
private struct DynamicIslandItemCard: View {
    let item: ClipboardEntry
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Main Clickable Area -> Paste Immediately
            Button(action: onPaste) {
                if let thumb = item.previewImage {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.black.opacity(0.65))
                            Image(nsImage: thumb)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 136, maxHeight: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .frame(width: 140, height: 78)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Image")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                if item.isPinned {
                                    Text("PINNED")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(AppTheme.warning)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(AppTheme.warning.opacity(0.16)))
                                }
                            }
                            Text(item.metadataLabel)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                            Text("\(item.relativeTimeString) • Click to paste")
                                .font(.system(size: 10.5))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.textPreview)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            if item.isPinned {
                                HStack(spacing: 3) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 8.5))
                                    Text("Saved")
                                        .font(.system(size: 9.5, weight: .semibold))
                                }
                                .foregroundColor(AppTheme.warning)
                            }
                            Text(item.metadataLabel)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted)
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                            Text(item.relativeTimeString)
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)

            // Right Action Controls: Paste Pill | Pin Toggle | Delete
            HStack(spacing: 6) {
                Button(action: onPaste) {
                    Text("Paste")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(isHovered ? .white : AppTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isHovered ? AppTheme.accent : Color.white.opacity(0.09))
                        )
                }
                .buttonStyle(.plain)

                // Pin / Unpin Button (Persists across Mac shutdown!)
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(item.isPinned ? AppTheme.warning : AppTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(item.isPinned ? AppTheme.warning.opacity(0.18) : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin item" : "Pin item (Saved permanently)")

                // Delete Single Item
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Delete item")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.095 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.16 : 0.06), lineWidth: 1)
                )
        )
        .animation(AppTheme.springSnappy, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
