import SwiftUI

struct InteractiveMouseView: View {
    @ObservedObject var engine: MouseEngine
    let activeProfile: AppProfile
    var onSelectButton: (MouseButtonKind) -> Void

    @Namespace private var tapModeSliderNamespace

    private var isForwardPressed: Bool {
        engine.pressedButtons.contains(MouseButtonKind.sideForward.rawValue)
    }
    private var isBackwardPressed: Bool {
        engine.pressedButtons.contains(MouseButtonKind.sideBackward.rawValue)
    }
    private var isLeftPressed: Bool {
        engine.pressedButtons.contains(MouseButtonKind.left.rawValue)
    }
    private var isRightPressed: Bool {
        engine.pressedButtons.contains(MouseButtonKind.right.rawValue)
    }
    private var isMiddlePressed: Bool {
        engine.pressedButtons.contains(MouseButtonKind.middle.rawValue)
    }

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 16,
            tintColor: AppTheme.accent,
            isHighlighted: !engine.pressedButtons.isEmpty
        ) {
            VStack(spacing: 14) {
                // Top Bar: Live Status + Liquid Glass Sliding Tap Mode Switcher + Swap Side Buttons
                HStack(spacing: 12) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(!engine.pressedButtons.isEmpty ? AppTheme.success : AppTheme.accent)
                            .frame(width: 7, height: 7)

                        Text(statusText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(!engine.pressedButtons.isEmpty ? AppTheme.success : AppTheme.textSecondary)
                    }

                    Spacer()

                    // Single Gliding Liquid Glass Segmented Slider: 1x Single | 2x Double | 3x Triple
                    HStack(spacing: 0) {
                        ForEach(TapCountKind.allCases) { tapMode in
                            let isSelected = engine.selectedTapMode == tapMode
                            Button(action: {
                                withAnimation(AppTheme.springSlider) {
                                    engine.selectedTapMode = tapMode
                                }
                            }) {
                                Text(tapMode.fullTitle)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 5.5)
                                    .contentShape(Capsule())
                                    .background(
                                        ZStack {
                                            if isSelected {
                                                LiquidGlassSlidingPill(accentTint: AppTheme.accent, isDarkNotchStyle: false)
                                                    .matchedGeometryEffect(id: "TapModeLiquidSlider", in: tapModeSliderNamespace)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    SmartTooltipManager.shared.show(
                                        icon: "hand.tap.fill",
                                        title: "Configure \(tapMode.fullTitle)",
                                        detail: "Assign a separate action when a mouse button is clicked \(tapMode.rawValue) time(s).",
                                        tint: AppTheme.accent
                                    )
                                } else {
                                    SmartTooltipManager.shared.hide()
                                }
                            }
                        }
                    }
                    .padding(3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.045))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(AppTheme.borderSubtle, lineWidth: 1)
                            )
                    )

                    Spacer()

                    // Minimalist Swap Side Polarity Button
                    LiquidIconButton(
                        icon: "arrow.up.arrow.down",
                        label: engine.swapSideButtons ? "Swapped" : "Swap Side",
                        tint: AppTheme.accent,
                        isActive: engine.swapSideButtons,
                        size: 28,
                        tooltipTitle: engine.swapSideButtons ? "Side Buttons: Swapped" : "Swap Forward & Backward",
                        tooltipDetail: "Invert the physical front and back thumb buttons if they feel reversed on your mouse."
                    ) {
                        withAnimation(AppTheme.springSnappy) {
                            engine.swapSideButtons.toggle()
                        }
                    }
                }

                // Center Minimalist Interactive Mouse Hardware Preview
                HStack(spacing: 28) {
                    // Left Side Thumb Buttons: Forward & Backward
                    VStack(alignment: .trailing, spacing: 10) {
                        UniformMouseCalloutChip(
                            icon: "arrow.up.circle.fill",
                            label: "Forward",
                            subtitle: "Side Button 1",
                            badge: activeProfile.mapping(for: .sideForward, tapCount: engine.selectedTapMode).effectiveBadge,
                            isPressed: isForwardPressed,
                            isSelected: engine.highlightedButtonForConfig == .sideForward
                        ) {
                            withAnimation(AppTheme.springSnappy) {
                                engine.highlightedButtonForConfig = .sideForward
                                onSelectButton(.sideForward)
                            }
                        }

                        UniformMouseCalloutChip(
                            icon: "arrow.down.circle.fill",
                            label: "Backward",
                            subtitle: "Side Button 2",
                            badge: activeProfile.mapping(for: .sideBackward, tapCount: engine.selectedTapMode).effectiveBadge,
                            isPressed: isBackwardPressed,
                            isSelected: engine.highlightedButtonForConfig == .sideBackward
                        ) {
                            withAnimation(AppTheme.springSnappy) {
                                engine.highlightedButtonForConfig = .sideBackward
                                onSelectButton(.sideBackward)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    // Center Precision Hardware Mouse Diagram
                    UniformMouseSilhouette(
                        isLeftPressed: isLeftPressed,
                        isRightPressed: isRightPressed,
                        isMiddlePressed: isMiddlePressed,
                        isForwardPressed: isForwardPressed,
                        isBackwardPressed: isBackwardPressed,
                        highlightedKind: engine.highlightedButtonForConfig
                    )
                    .frame(width: 88, height: 126)

                    // Right Side: Middle Scroll Wheel Click
                    VStack(alignment: .leading, spacing: 10) {
                        UniformMouseCalloutChip(
                            icon: "circle.grid.cross.fill",
                            label: "Middle Wheel",
                            subtitle: "Scroll Click",
                            badge: activeProfile.mapping(for: .middle, tapCount: engine.selectedTapMode).effectiveBadge,
                            isPressed: isMiddlePressed,
                            isSelected: engine.highlightedButtonForConfig == .middle
                        ) {
                            withAnimation(AppTheme.springSnappy) {
                                engine.highlightedButtonForConfig = .middle
                                onSelectButton(.middle)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
        }
    }

    private var statusText: String {
        if let last = engine.lastDetectedButton, !engine.pressedButtons.isEmpty {
            return "Pressed: \(last.shortName) (\(engine.lastDetectedTapCount)×)"
        }
        return "Press any mouse button to test live"
    }
}

private struct UniformMouseCalloutChip: View {
    let icon: String
    let label: String
    let subtitle: String
    let badge: String
    let isPressed: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(isPressed || isSelected ? .white : AppTheme.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(AppTheme.textMuted)
                }

                Text(badge)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(isPressed ? .white : (isSelected ? .white : AppTheme.accent))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule()
                            .fill(isPressed || isSelected ? AppTheme.accent : AppTheme.accentSoft)
                    )
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isPressed
                            ? AppTheme.accent.opacity(0.32)
                            : Color.white.opacity(isSelected ? 0.09 : (isHovered ? 0.065 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isPressed || isSelected
                                    ? AppTheme.accent.opacity(0.65)
                                    : Color.white.opacity(isHovered ? 0.14 : 0.07),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 1.03 : 1.0)
            .animation(AppTheme.springSnappy, value: isPressed)
            .animation(AppTheme.springSnappy, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct UniformMouseSilhouette: View {
    let isLeftPressed: Bool
    let isRightPressed: Bool
    let isMiddlePressed: Bool
    let isForwardPressed: Bool
    let isBackwardPressed: Bool
    let highlightedKind: MouseButtonKind?

    var body: some View {
        ZStack {
            // Outer Mouse Body
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.03)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 76, height: 122)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1.2)
                )

            // Left & Right Primary Clicks
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isLeftPressed ? AppTheme.accent.opacity(0.65) : Color.white.opacity(0.06))
                .frame(width: 28, height: 40)
                .offset(x: -15, y: -30)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRightPressed ? AppTheme.accent.opacity(0.65) : Color.white.opacity(0.06))
                .frame(width: 28, height: 40)
                .offset(x: 15, y: -30)

            // Middle Scroll Wheel
            Capsule()
                .fill(isMiddlePressed || highlightedKind == .middle ? AppTheme.accent : Color.white.opacity(0.28))
                .frame(width: 10, height: 24)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(highlightedKind == .middle ? 0.65 : 0.15), lineWidth: 1)
                )
                .offset(x: 0, y: -30)
                .scaleEffect(isMiddlePressed ? 1.15 : 1.0)

            // Left Side Thumb Forward Button
            Capsule()
                .fill(isForwardPressed || highlightedKind == .sideForward ? AppTheme.accent : Color.white.opacity(0.25))
                .frame(width: 9, height: 22)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(highlightedKind == .sideForward ? 0.75 : 0.15), lineWidth: 1)
                )
                .offset(x: -39, y: -6)
                .scaleEffect(isForwardPressed ? 1.22 : 1.0)

            // Left Side Thumb Backward Button
            Capsule()
                .fill(isBackwardPressed || highlightedKind == .sideBackward ? AppTheme.accent : Color.white.opacity(0.25))
                .frame(width: 9, height: 22)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(highlightedKind == .sideBackward ? 0.75 : 0.15), lineWidth: 1)
                )
                .offset(x: -39, y: 20)
                .scaleEffect(isBackwardPressed ? 1.22 : 1.0)
        }
        .animation(AppTheme.springSnappy, value: isForwardPressed)
        .animation(AppTheme.springSnappy, value: isBackwardPressed)
        .animation(AppTheme.springSnappy, value: isMiddlePressed)
        .animation(AppTheme.springSnappy, value: highlightedKind)
    }
}
