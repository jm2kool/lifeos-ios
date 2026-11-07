import SwiftUI

/// On the full player, just above the song's name: the line being sung, and the next one smaller in a darker
/// grey, sliding up as the song goes. Tap to open the full lyrics. Shows nothing for songs without synced lyrics.
struct NowPlayingLyrics: View {
    let item: QueueItem
    var open: () -> Void = {}
    @Environment(PlaybackCoordinator.self) private var player
    @State private var lyrics: Lyrics?

    var body: some View {
        Group {
            if let lyrics, lyrics.isSynced, UserDefaults.standard.string(forKey: "lyricsSource") != "off" {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    let i = lyrics.activeIndex(at: player.currentTime + 0.25)
                    lines(lyrics, index: i)
                }
                .transition(.opacity)
            }
        }
        .task(id: item.id) {
            lyrics = nil
            let found = await LyricsStore.lyrics(for: item)
            withAnimation(.liner) { lyrics = found }
        }
    }

    private func lines(_ lyrics: Lyrics, index i: Int?) -> some View {
        let current = i.map { lyrics.lines[$0].text } ?? ""
        let nextIndex = (i ?? -1) + 1
        let next = lyrics.lines.indices.contains(nextIndex) ? lyrics.lines[nextIndex].text : ""
        return Button(action: open) {
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
            .id(i ?? -1)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)))
        }
        .buttonStyle(.plain)
        .frame(height: 64, alignment: .bottomLeading)
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
