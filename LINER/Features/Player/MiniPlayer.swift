import SwiftUI

/// The mini player in the tab bar's bottom accessory, Apple Music style. Tap to open the full player.
struct MiniPlayer: View {
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let item = player.current {
            HStack(spacing: 12) {
                QueueItemArtwork(item: item, cornerRadius: 6).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if placement != .inline {
                        Text(item.artist).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 34, height: 34)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                if placement != .inline {
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 16)).frame(width: 34, height: 34) }
                        .accessibilityLabel("Next")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture { player.showFullPlayer = true }
            .accessibilityAction(named: "Open player") { player.showFullPlayer = true }
        } else {
            HStack {
                Image(systemName: "music.note").foregroundStyle(Palette.faint)
                Text("Not playing").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
        }
    }
}
