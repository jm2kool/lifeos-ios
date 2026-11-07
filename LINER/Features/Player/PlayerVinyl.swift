import SwiftUI

/// The player's vinyl look: the current song as a spinning record. Drag it to scratch through the song,
/// tap it to pause or play. It spins at 33⅓ rpm and eases to a stop when paused.
struct PlayerVinyl: View {
    let item: QueueItem
    @Environment(PlaybackCoordinator.self) private var player
    @State private var spin = SpinState()
    @State private var scrub: Double?
    @State private var lastSeek = Date.distantPast
    @State private var startTime = 0.0
    @State private var cover: Data?

    private var record: VinylRecord {
        VinylRecord(id: item.coverKey, title: item.title, artist: item.artist, year: item.song?.releaseDate.map { Calendar.current.component(.year, from: $0) },
                    albumID: item.song?.albumID, coverData: cover, tracks: [])
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            TimelineView(.animation) { ctx in
                let angle = spin.angle(at: ctx.date, playing: player.isPlaying && scrub == nil) + (scrub ?? 0)
                RecordDisc(record: record, side: "A")
                    .rotationEffect(.radians(angle))
            }
            .overlay(RecordSheen())
            .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(scratch(size: size))
            .onTapGesture { player.togglePlayPause(); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: item.id) {
            if case .local(let t) = item, let url = t.coverURL { cover = try? Data(contentsOf: url) } else { cover = nil }
        }
        .accessibilityElement()
        .accessibilityLabel("Record: \(item.title)")
        .accessibilityHint("Double-tap to play or pause. Drag around the record to scratch through the song.")
    }

    /// Angular drag → seek: one turn is 1.8 s at 33⅓ rpm, sped up ×4 so a scratch covers real distance.
    private func scratch(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                if scrub == nil { startTime = player.currentTime }
                let c = CGPoint(x: size / 2, y: size / 2)
                var d = Double(atan2(v.location.y - c.y, v.location.x - c.x) - atan2(v.startLocation.y - c.y, v.startLocation.x - c.x))
                if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
                scrub = d
                if Date.now.timeIntervalSince(lastSeek) > 0.15 {
                    lastSeek = .now
                    player.seek(to: startTime + d / (2 * .pi) * 1.8 * 4)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                if let d = scrub { player.seek(to: startTime + d / (2 * .pi) * 1.8 * 4); spin.carry(d) }
                scrub = nil
            }
    }
}
