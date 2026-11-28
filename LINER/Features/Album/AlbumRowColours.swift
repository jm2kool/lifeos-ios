import SwiftUI

/// The number column on a coloured album page: the track number, or moving bars on the song that's playing.
struct AlbumTrackNumber: View {
    let number: Int
    let itemID: String
    let colours: AlbumColours
    var scale: CGFloat = 1
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        if player.current?.id == itemID {
            PlayingBars(colour: colours.accent, playing: player.isPlaying)
        } else {
            Text("\(number)").albumFace(17 * scale, fallback: .serif(17 * scale)).monospacedDigit().foregroundStyle(colours.secondary)
        }
    }
}

/// Three little bars that bounce while the song plays and rest when it's paused.
struct PlayingBars: View {
    let colour: Color
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !playing || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<3, id: \.self) { k in
                    Capsule().fill(colour)
                        .frame(width: 3.5, height: playing ? 5 + 9 * abs(sin(t * (5 + Double(k)) + Double(k) * 1.3)) : 5)
                }
            }
            .frame(height: 15, alignment: .bottom)
        }
        .accessibilityLabel(playing ? "Playing" : "Paused")
    }
}

/// A song title on a coloured album page: the page's title colour, or its accent when it's the one playing.
struct AlbumRowTitle: ViewModifier {
    let itemID: String
    let colours: AlbumColours
    @Environment(PlaybackCoordinator.self) private var player

    func body(content: Content) -> some View {
        content.foregroundStyle(player.current?.id == itemID ? colours.accent : colours.primary)
    }
}

extension View {
    /// Colours a song row's title when it sits on a coloured album page.
    @ViewBuilder func albumRowTitle(_ itemID: String, _ colours: AlbumColours?) -> some View {
        if let colours { modifier(AlbumRowTitle(itemID: itemID, colours: colours)) } else { self }
    }
}

#Preview {
    VStack(spacing: 20) {
        PlayingBars(colour: .pink, playing: true)
        PlayingBars(colour: .pink, playing: false)
    }
    .padding().background(Color.indigo)
}
