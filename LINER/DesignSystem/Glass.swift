import SwiftUI

/// A floating round Liquid Glass button (back, •••, play, passport, heart).
struct GlassCircleButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// A capsule glass button with an icon and a word (Play, Shuffle).
struct GlassPillButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(prominent ? AnyPrimitiveButtonStyle(.linerPrimary) : AnyPrimitiveButtonStyle(.glass))
        .controlSize(.large)
    }
}

/// Lets a view pick between glass styles at run time.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

#Preview {
    VStack(spacing: 20) {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassCircleButton(systemImage: "chevron.left", label: "Back") {}
                GlassCircleButton(systemImage: "ellipsis", label: "More") {}
            }
        }
        HStack { GlassPillButton(title: "Play", systemImage: "play.fill", prominent: true) {}; GlassPillButton(title: "Shuffle", systemImage: "shuffle") {} }
    }
    .padding().background(LinearGradient(colors: [.orange, .black], startPoint: .top, endPoint: .bottom))
}

/// The primary action: Liquid Glass prominent, filled white with black text (the app's white tint would
/// otherwise make the label white on white).
struct LinerPrimaryStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.foregroundStyle(.black)
        }
        .buttonStyle(.glassProminent)
        .tint(.white)
    }
}

extension PrimitiveButtonStyle where Self == LinerPrimaryStyle {
    static var linerPrimary: LinerPrimaryStyle { LinerPrimaryStyle() }
}

/// Switches with a grey "on" track, so the white knob stays visible in the monochrome theme.
struct LinerToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(Color(white: 0.42))
    }
}
