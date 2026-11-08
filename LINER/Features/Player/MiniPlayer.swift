import SwiftUI

/// The mini player in the tab bar's bottom accessory, Apple Music style. Tap to open the full player; swipe left
/// for the next song, right for the previous one (the song slides with your finger).
struct MiniPlayer: View {
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var drag: CGFloat = 0
    /// Which way the last swipe went, so the next song slides in from the right side.
    @State private var forward = true

    var body: some View {
        if let item = player.current {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    QueueItemArtwork(item: item, cornerRadius: 6).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if placement != .inline {
                            Text(item.artist).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .id(item.id)
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .offset(x: drag)
                .opacity(1 - min(0.6, abs(drag) / 160))
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
            .clipped()
            .animation(.smooth(duration: 0.35), value: item.id)
            .onTapGesture { player.showFullPlayer = true }
            .simultaneousGesture(swipe)
            .accessibilityAction(named: "Next song") { player.next() }
            .accessibilityAction(named: "Previous song") { previousSong() }
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

    /// Horizontal swipes only, so scrolling the page under the bar still works.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                drag = v.translation.width * 0.6
            }
            .onEnded { v in
                let dx = v.translation.width
                let flick = v.predictedEndTranslation.width
                let horizontal = abs(dx) > abs(v.translation.height)
                withAnimation(.smooth(duration: 0.3)) { drag = 0 }
                guard horizontal, abs(dx) > 50 || abs(flick) > 140 else { return }
                forward = (abs(dx) > 50 ? dx : flick) < 0
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if forward { player.next() } else { previousSong() }
            }
    }

    /// Straight to the song before (not back to the start of this one, as the ⏮ button does after 3 s).
    private func previousSong() {
        if player.index > 0 { player.jump(to: player.index - 1) } else { player.seek(to: 0) }
    }
}
