import SwiftUI

enum Theme {
    static let accent = Color(hex: 0xFB7299)
    static let accentDeep = Color(hex: 0xE5487C)
    static let accentSoft = Color(hex: 0xFB7299).opacity(0.14)
    static let blue = Color(hex: 0x6C8CFF)
    static let violet = Color(hex: 0x9B7BFF)
    static let mint = Color(hex: 0x5AC8B0)
    static let sidebarWidth: CGFloat = 226
    static let contentPadding: CGFloat = 32
    static let playerHeight: CGFloat = 58
    static let cardRadius: CGFloat = 14
    static let coverRadius: CGFloat = 12
    static let sectionSpacing: CGFloat = 34
    static let windowRadius: CGFloat = 18

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFF9DB5), accent, accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var pageGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0xFB7299).opacity(0.07),
                Color.clear,
                Color(hex: 0x6C8CFF).opacity(0.045)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension View {
    func panelBackground(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PlatformColor.controlBackground.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    func hoverLift(_ hovering: Bool) -> some View {
        scaleEffect(hovering ? 1.012 : 1)
            .shadow(
                color: Color.black.opacity(hovering ? 0.16 : 0.07),
                radius: hovering ? 14 : 8,
                y: hovering ? 7 : 4
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovering)
    }
}

#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = state
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.state = state
    }
}
#endif

struct AmbientBackdrop: View {
    var accent: Color = Theme.accent

    var body: some View {
        ZStack {
            PlatformColor.windowBackground
            Theme.pageGradient
            GeometryReader { proxy in
                Circle()
                    .fill(accent.opacity(0.13))
                    .frame(width: proxy.size.width * 0.46)
                    .blur(radius: 90)
                    .offset(x: -proxy.size.width * 0.16, y: -proxy.size.height * 0.24)
                Circle()
                    .fill(Theme.blue.opacity(0.08))
                    .frame(width: proxy.size.width * 0.38)
                    .blur(radius: 100)
                    .offset(x: proxy.size.width * 0.58, y: proxy.size.height * 0.12)
                Circle()
                    .fill(Theme.violet.opacity(0.06))
                    .frame(width: proxy.size.width * 0.34)
                    .blur(radius: 90)
                    .offset(x: proxy.size.width * 0.22, y: proxy.size.height * 0.72)
            }
        }
        .ignoresSafeArea()
    }
}
