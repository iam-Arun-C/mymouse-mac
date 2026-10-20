import SwiftUI
import AppKit
import Carbon.HIToolbox

struct ShortcutRecorderSheet: View {
    let title: String
    let subtitle: String
    let showNameField: Bool
    @State var customName: String = ""
    @State var recordedCombo: CustomKeyCombo?
    var onSave: (String, CustomKeyCombo) -> Void
    var onCancel: () -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if showNameField {
                TextField("Button Name (optional, e.g. Print, Export, Copy)...", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // Keycap Display Box
            VStack(spacing: 8) {
                if let combo = recordedCombo {
                    HStack(spacing: 6) {
                        ForEach(combo.displayString.components(separatedBy: " "), id: \.self) { part in
                            Text(part)
                                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AppTheme.accentSoft)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(AppTheme.accent, lineWidth: 1.2)
                                        )
                                )
                        }
                    }
                    Text("Press another key combination to change")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                } else {
                    Text("Press any key combination on your keyboard now...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                    Text("(e.g. ⌘ + P, ⌘ + C, ⌃ + ⌥ + S, F5)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
                    )
            )

            // Footer Actions
            HStack {
                Button("Cancel") {
                    stopListening()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Key") {
                    if let combo = recordedCombo {
                        stopListening()
                        onSave(customName, combo)
                    }
                }
                .disabled(recordedCombo == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 390)
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    private func startListening() {
        stopListening()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let ignoredModifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if ignoredModifierKeyCodes.contains(event.keyCode) {
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let combo = CustomKeyCombo(
                keyCode: event.keyCode,
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option),
                control: flags.contains(.control)
            )
            DispatchQueue.main.async {
                self.recordedCombo = combo
            }
            return nil
        }
    }

    private func stopListening() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
