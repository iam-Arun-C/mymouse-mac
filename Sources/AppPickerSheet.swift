import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DiscoveredAppItem: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let appName: String
    let bundleIdentifier: String
    let appPath: String?
    let isRunning: Bool
}

struct AppPickerSheet: View {
    var existingBundleIDs: Set<String>
    var onSelectApp: (DiscoveredAppItem) -> Void
    var onCancel: () -> Void

    @State private var searchText: String = ""
    @State private var discoveredApps: [DiscoveredAppItem] = []

    private var filteredApps: [DiscoveredAppItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return discoveredApps }
        return discoveredApps.filter {
            $0.appName.lowercased().contains(q) || $0.bundleIdentifier.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Application Profile")
                        .font(.system(size: 17, weight: .bold))
                    Text("Choose a running or installed app to customize your mouse buttons specifically for it.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Browse App...") {
                    browseForApplication()
                }
            }

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps (e.g. Photoshop, Chrome, Final Cut, VS Code)...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
            )

            // App List
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredApps) { item in
                        let alreadyAdded = existingBundleIDs.contains(item.bundleIdentifier.lowercased())
                        Button(action: {
                            onSelectApp(item)
                        }) {
                            HStack(spacing: 12) {
                                appIcon(for: item)
                                    .resizable()
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.appName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)

                                        if item.isRunning {
                                            Text("Running")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                        }
                                    }

                                    Text(item.bundleIdentifier)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(alreadyAdded ? "Select" : "Add Profile")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(AppTheme.accentSoft)
                                    )
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.03))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 310)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            loadApps()
        }
    }

    private func appIcon(for item: DiscoveredAppItem) -> Image {
        if let path = item.appPath, FileManager.default.fileExists(atPath: path) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "app.fill")
    }

    private func loadApps() {
        var map: [String: DiscoveredAppItem] = [:]

        // 1. Running regular applications
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            guard let bundleID = running.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { continue }
            let name = running.localizedName ?? bundleID
            let path = running.bundleURL?.path
            map[bundleID.lowercased()] = DiscoveredAppItem(
                appName: name,
                bundleIdentifier: bundleID,
                appPath: path,
                isRunning: true
            )
        }

        // 2. Installed apps in /Applications and /System/Applications
        let appDirs = ["/Applications", "/System/Applications"]
        for dir in appDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for entry in items where entry.hasSuffix(".app") {
                let fullPath = (dir as NSString).appendingPathComponent(entry)
                if let bundle = Bundle(path: fullPath),
                   let bundleID = bundle.bundleIdentifier,
                   bundleID != Bundle.main.bundleIdentifier {
                    let key = bundleID.lowercased()
                    if map[key] == nil {
                        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                            ?? (entry as NSString).deletingPathExtension
                        map[key] = DiscoveredAppItem(
                            appName: name,
                            bundleIdentifier: bundleID,
                            appPath: fullPath,
                            isRunning: false
                        )
                    }
                }
            }
        }

        discoveredApps = map.values.sorted { a, b in
            if a.isRunning != b.isRunning { return a.isRunning && !b.isRunning }
            return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
        }
    }

    private func browseForApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application (.app)"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let item = DiscoveredAppItem(
                    appName: name,
                    bundleIdentifier: bundleID,
                    appPath: url.path,
                    isRunning: false
                )
                onSelectApp(item)
            }
        }
    }
}
