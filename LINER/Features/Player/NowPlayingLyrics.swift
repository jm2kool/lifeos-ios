import SwiftUI

/// On the full player, just above the song's name: the line being sung, and the next one smaller in a darker
/// grey, sliding up as the song goes. Tap to open the full lyrics. It always keeps its place (so nothing jumps):
/// while lyrics load, and for songs without synced lyrics, it says so quietly.
struct NowPlayingLyrics: View {
    let item: QueueItem
    var open: () -> Void = {}
    @Environment(PlaybackCoordinator.self) private var player
    @State private var lyrics: Lyrics?
    @State private var loading = true

    var body: some View {
        Group {
            if let lyrics, lyrics.isSynced {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    let i = lyrics.activeIndex(at: player.currentTime + 0.25)
                    let next = lyrics.lines.indices.contains((i ?? -1) + 1) ? lyrics.lines[(i ?? -1) + 1].text : ""
                    lines(current: i.map { lyrics.lines[$0].text } ?? "", next: next, index: i ?? -1)
                }
            } else if UserDefaults.standard.string(forKey: "lyricsSource") == "off" {
                lines(current: "♪", next: "Lyrics are off in Settings", index: -2)
            } else if loading {
                lines(current: "♪", next: "Finding the lyrics…", index: -3)
            } else {
                lines(current: "♪", next: lyrics?.plain != nil ? "Lyrics without timings — tap to read" : "No lyrics for this song", index: -4)
            }
        }
        .task(id: item.id) {
            loading = true
            let found = await LyricsStore.lyrics(for: item)
            withAnimation(.liner) { lyrics = found; loading = false }
        }
    }

    private func lines(current: String, next: String, index i: Int) -> some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                Text(current.isEmpty ? "♪" : current)
                    .font(.serif(21, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.8)
                if !next.isEmpty {
                    Text(next)
                        .font(.serif(15)).foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(i)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)))
        }
        .buttonStyle(.plain)
        .frame(height: 80, alignment: .bottomLeading)
        .clipped()
        .animation(.smooth(duration: 0.45), value: i)
        .accessibilityLabel(current.isEmpty ? "Lyrics" : current)
        .accessibilityHint("Double-tap to open the lyrics")
    }
}

#Preview {
    NowPlayingLyrics(item: .library(PreviewData.snapshot.songs[0]))
        .padding().background(.black)
        .environment(PreviewData.library).environment(PreviewData.player).modelContainer(Store.shared.container)
        .preferredColorScheme(.dark)
}
