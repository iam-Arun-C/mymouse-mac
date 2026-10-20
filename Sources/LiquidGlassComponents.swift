import SwiftUI
import AppKit

// MARK: - Unified Design System: Color Science, Typography & Physics
enum AppTheme {
    // 1. Standard Color Science (Obsidian Graphite + Specular Silver/Blue Glass)
    static let windowBgTop = Color(red: 0.06, green: 0.065, blue: 0.08)
    static let windowBgBottom = Color(red: 0.035, green: 0.04, blue: 0.05)

    // Unified Primary Accent (Apple Pro Electric Blue)
    static let accent = Color(red: 0.24, green: 0.56, blue: 1.0)
    static let accentSoft = Color(red: 0.24, green: 0.56, blue: 1.0).opacity(0.18)

    // Semantic Status Colors (Used sparingly and consistently)
    static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

    // Surface Elevations
    static let surfaceLow = Color.white.opacity(0.035)
    static let surfaceMedium = Color.white.opacity(0.06)
    static let surfaceHigh = Color.white.opacity(0.10)
    static let borderSubtle = Color.white.opacity(0.08)
    static let borderHighlight = Color.white.opacity(0.22)

    // Text Hierarchy
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.58)
    static let textMuted = Color.white.opacity(0.38)

    // 2. Standard Spring Physics (Critically damped for 120Hz ProMotion with zero stutter/overshoot)
    static let springSlider = Animation.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)
    static let springSnappy = Animation.spring(response: 0.22, dampingFraction: 0.85, blendDuration: 0.06)
    static let springNotchExpand = Animation.spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.10)
    static let springNotchCollapse = Animation.spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.08)
}

// MARK: - Reusable Liquid Glass Sliding Pill Indicator (Zero Offscreen Shadow Blur for 120Hz)
struct LiquidGlassSlidingPill: View {
    var accentTint: Color = AppTheme.accent
    var isDarkNotchStyle: Bool = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: isDarkNotchStyle ? [
                            Color.white.opacity(0.20),
                            accentTint.opacity(0.22),
                            Color.white.opacity(0.09)
                        ] : [
                            accentTint.opacity(0.85),
                            accentTint.opacity(0.62)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Top specular liquid glass rim reflection
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(isDarkNotchStyle ? 0.42 : 0.50),
                            Color.white.opacity(0.08)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
        }
    }
}

// MARK: - Instant Smart Custom Tooltip Manager
final class SmartTooltipManager: ObservableObject {
    static let shared = SmartTooltipManager()

    struct TooltipContent: Equatable {
        let icon: String
        let title: String
        let detail: String
        let tint: Color
    }

    @Published var current: TooltipContent? = nil

    func show(icon: String, title: String, detail: String, tint: Color = AppTheme.accent) {
        guard !title.isEmpty else { return }
        withAnimation(AppTheme.springSnappy) {
            current = TooltipContent(icon: icon, title: title, detail: detail, tint: tint)
        }
    }

    func hide() {
        withAnimation(.easeOut(duration: 0.14)) {
            current = nil
        }
    }
}

// MARK: - Smart Custom Tooltip Floating Modal HUD
struct SmartTooltipHUD: View {
    @ObservedObject var manager = SmartTooltipManager.shared

    var body: some View {
        if let tip = manager.current {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tip.tint.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: tip.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tip.tint)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(tip.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    if !tip.detail.isEmpty {
                        Text(tip.detail)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    VisualEffectGlass(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(Capsule(style: .continuous))

                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.72))

                    Capsule(style: .continuous)
                        .stroke(AppTheme.borderHighlight, lineWidth: 1)
                }
            )
            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Native macOS NSVisualEffectView Wrapper
struct VisualEffectGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Uniform Apple-Standard Surface Card Container
struct LiquidGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    var tintColor: Color = AppTheme.accent
    var isHighlighted: Bool = false
    let content: Content

    init(
        cornerRadius: CGFloat = 14,
        tintColor: Color = AppTheme.accent,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(isHighlighted ? 0.085 : 0.045),
                            isHighlighted ? tintColor.opacity(0.08) : Color.white.opacity(0.025)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            isHighlighted ? tintColor.opacity(0.55) : Color.white.opacity(0.12),
                            isHighlighted ? tintColor.opacity(0.20) : Color.white.opacity(0.04)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )

            content
        }
    }
}

// MARK: - Uniform Minimalist Icon / Pill Button with Instant Smart Tooltip
struct LiquidIconButton: View {
    let icon: String
    var label: String? = nil
    var tint: Color = AppTheme.accent
    var isActive: Bool = false
    var size: CGFloat = 30
    var tooltipTitle: String = ""
    var tooltipDetail: String = ""
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(isActive ? .white : (isHovered ? AppTheme.textPrimary : AppTheme.textSecondary))

                if let label = label {
                    Text(label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(isActive ? .white : AppTheme.textPrimary)
                }
            }
            .padding(.horizontal, label != nil ? 11 : 0)
            .frame(minWidth: size, minHeight: size)
            .background(
                ZStack {
                    if isActive {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [tint, tint.opacity(0.78)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isHovered ? 0.11 : 0.055))
                    }

                    Capsule(style: .continuous)
                        .stroke(
                            Color.white.opacity(isActive ? 0.32 : (isHovered ? 0.18 : 0.08)),
                            lineWidth: 1
                        )
                }
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(AppTheme.springSnappy, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering && !tooltipTitle.isEmpty {
                SmartTooltipManager.shared.show(
                    icon: icon,
                    title: tooltipTitle,
                    detail: tooltipDetail,
                    tint: tint
                )
            } else if !hovering {
                SmartTooltipManager.shared.hide()
            }
        }
    }
}
