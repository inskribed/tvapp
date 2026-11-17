import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The user's accent color (Settings > Appearance), plus the small highlight that goes with it.
struct AccentPreset: Identifiable {
    let name: String
    let color: Color
    let highlight: Color
    var id: String { name }
}

enum Brand {
    static let presets: [AccentPreset] = [
        AccentPreset(name: "Orka teal", color: Color(hex: 0x1FE3CC), highlight: Color(hex: 0xC9FF3F)),
        AccentPreset(name: "Lime", color: Color(hex: 0xC9FF3F), highlight: Color(hex: 0x1FE3CC)),
        AccentPreset(name: "Sky", color: Color(hex: 0x5AC8FA), highlight: Color(hex: 0xA5E4FF)),
        AccentPreset(name: "Mint", color: Color(hex: 0x4CD9A0), highlight: Color(hex: 0xA6F0D1)),
        AccentPreset(name: "Amber", color: Color(hex: 0xFFB84D), highlight: Color(hex: 0xFFDA9C)),
        AccentPreset(name: "Coral", color: Color(hex: 0xFF7A6B), highlight: Color(hex: 0xFFB9B0)),
        AccentPreset(name: "Rose", color: Color(hex: 0xFF6FAE), highlight: Color(hex: 0xFFB4D6)),
        AccentPreset(name: "Violet", color: Color(hex: 0xB48CFF), highlight: Color(hex: 0xD9C4FF)),
        AccentPreset(name: "Periwinkle", color: Color(hex: 0x8AA4FF), highlight: Color(hex: 0xC0CEFF)),
        AccentPreset(name: "Silver", color: Color(hex: 0xC8CCD6), highlight: Color(hex: 0xE8EAF0)),
    ]

    static let background = Color(hex: 0x0B0B0F)
    static let live = Color(hex: 0xFF4D4D)
    static let star = Color(hex: 0xFFC94D)
}

/// Dark base with soft accent glows, so the glass has something to catch the light.
struct OrkaBackground: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Brand.background
            RadialGradient(colors: [model.accent.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [model.highlight.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

// MARK: Glass

extension View {
    /// A rounded glass panel (iOS 26 Liquid Glass), optionally tinted and touch-reactive.
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// A light, cheap panel for long lists, where dozens of glass layers would cost smoothness.
    func listPanel(cornerRadius: CGFloat = 16) -> some View {
        background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if interactive {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content.glassEffect(.regular.tint(tint), in: shape)
        }
    }
}
