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
                // The whole circle takes the tap, not just the glyph's strokes (a plain button only hit-tests what's drawn).
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(prominent ? AnyPrimitiveButtonStyle(.linerPrimary) : AnyPrimitiveButtonStyle(.linerGlass))
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

/// The primary action: always white glass with black text, whatever tint is around it.
struct LinerPrimaryStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.foregroundStyle(.black).singleLineLabel()
        }
        .buttonStyle(.glassProminent)
        .tint(.white)
    }
}

/// Liquid Glass button: always white on clear glass (never tinted by its surroundings), label on one line.
struct LinerGlassStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.foregroundStyle(.white).singleLineLabel()
        }
        .buttonStyle(.glass)
        .tint(.white)
    }
}

extension PrimitiveButtonStyle where Self == LinerGlassStyle {
    static var linerGlass: LinerGlassStyle { LinerGlassStyle() }
}

extension View {
    /// Button text never breaks onto a second line: it shrinks to at most 70 %, then truncates.
    func singleLineLabel() -> some View {
        lineLimit(1).minimumScaleFactor(0.7).allowsTightening(true)
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

/// Apple Music-style transport for albums and lists: [shuffle] [ ▶ Play ] [optional circle], centred.
struct PlayShuffleIcons<Trailing: View>: View {
    let play: () -> Void
    let shuffle: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                GlassCircleButton(systemImage: "shuffle", label: "Shuffle", size: 56, action: shuffle)
                Button(action: play) {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .frame(width: 170, height: 56)
                }
                .buttonStyle(.linerPrimary)
                .buttonBorderShape(.capsule)
                trailing
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension PlayShuffleIcons where Trailing == EmptyView {
    init(play: @escaping () -> Void, shuffle: @escaping () -> Void) {
        self.init(play: play, shuffle: shuffle) { EmptyView() }
    }
}

/// Apple Music-style artist transport: [left circle] [big ▶] [right circle], centred.
struct ArtistTransport<Leading: View, Trailing: View>: View {
    let play: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GlassEffectContainer(spacing: 22) {
            HStack(spacing: 22) {
                leading
                Button(action: play) {
                    Image(systemName: "play.fill").font(.system(size: 30, weight: .bold)).offset(x: 2)
                        .frame(width: 84, height: 84)
                }
                .buttonStyle(.linerPrimary)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Play")
                trailing
            }
        }
        .frame(maxWidth: .infinity)
    }
}
