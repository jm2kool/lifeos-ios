import SwiftUI

/// Tap the middle of the record and its setlist springs out of the label: a little paper card, taped on at a
/// jaunty angle, with every song by side. Pick one and the card tucks back into the label, the needle drops and
/// that song plays. Tap outside it (or ✕) to put it away.
struct SetlistCard: View {
    let record: VinylRecord
    let currentID: String?
    var tint: Color = .white
    let pick: (Int) -> Void
    let close: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setlist").font(.system(size: 10, weight: .bold)).tracking(2.4).textCase(.uppercase).foregroundStyle(tint)
                    Text(record.title).font(.serif(22)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 30, height: 30)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Put the setlist away")
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(record.sideList, id: \.name) { side in
                            Text("Side \(side.name)").font(.system(size: 10, weight: .semibold)).tracking(2).textCase(.uppercase)
                                .foregroundStyle(Palette.label).padding(.top, 10).padding(.bottom, 2)
                            ForEach(side.range, id: \.self) { i in row(i, side: side).id(i) }
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 18)
                }
                .onAppear {
                    if let i = record.tracks.firstIndex(where: { $0.id == currentID }) { proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.1)))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
        }
        // A strip of tape holding it on.
        .overlay(alignment: .top) {
            Rectangle().fill(Color(white: 0.85).opacity(0.22)).frame(width: 74, height: 20).rotationEffect(.degrees(-4)).offset(y: -9)
                .allowsHitTesting(false)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.08)) { shown = true } }
    }

    private func row(_ i: Int, side: VinylSide) -> some View {
        let item = record.tracks[i], playing = item.id == currentID
        let order = Double(i)
        return Button { pick(i) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Group {
                    if playing { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(tint) }
                    else { Text("\(side.name)\(i - side.range.lowerBound + 1)").foregroundStyle(Palette.faint) }
                }
                .font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 26, alignment: .leading)
                Text(item.title).font(.serif(17)).foregroundStyle(playing ? tint : .white).lineLimit(1)
                Spacer(minLength: 6)
                Text(item.duration.trackTime).font(.system(size: 11)).foregroundStyle(Palette.label).monospacedDigit()
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The songs tumble in one after another.
        .opacity(shown ? 1 : 0)
        .offset(x: shown ? 0 : -14)
        .rotationEffect(.degrees(shown ? 0 : -6), anchor: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.1 + min(order, 12) * 0.03), value: shown)
        .accessibilityLabel("\(side.name)\(i - side.range.lowerBound + 1), \(item.title)\(playing ? ", playing" : "")")
        .accessibilityHint("Plays this song")
    }
}

/// The card coming out of (and going back into) the record's label: from a dot at the centre, spinning out to
/// a slight tilt with a bounce.
private struct LabelSpin: ViewModifier {
    let scale: CGFloat
    let angle: Double
    let opacity: Double
    func body(content: Content) -> some View {
        content.scaleEffect(scale).rotationEffect(.degrees(angle)).opacity(opacity)
    }
}

extension AnyTransition {
    static var outOfTheLabel: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(active: LabelSpin(scale: 0.08, angle: -160, opacity: 0),
                                              identity: LabelSpin(scale: 1, angle: -2.5, opacity: 1))
                .animation(.spring(response: 0.55, dampingFraction: 0.66)),
            removal: AnyTransition.modifier(active: LabelSpin(scale: 0.08, angle: 120, opacity: 0),
                                            identity: LabelSpin(scale: 1, angle: -2.5, opacity: 1))
                .animation(.easeIn(duration: 0.3)))
    }
}

/// Puts the record on from the song picked: jumps there when the record is already the queue, else starts it.
@MainActor
enum SetlistPlay {
    static func play(_ record: VinylRecord, at i: Int, player: PlaybackCoordinator) {
        guard record.tracks.indices.contains(i) else { return }
        if !player.shuffle, player.queue.map(\.id) == record.tracks.map(\.id) { player.jump(to: i) }
        else { player.play(record.tracks, startAt: i, openPlayer: false) }
        VinylSounds.shared.needleDrop()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

#Preview {
    SetlistCard(record: .album(PreviewData.snapshot.albums[0], PreviewData.snapshot), currentID: nil, tint: .orange, pick: { _ in }, close: {})
        .frame(width: 320, height: 360).padding(40).background(.black)
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
