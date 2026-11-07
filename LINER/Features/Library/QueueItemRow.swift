import SwiftUI

/// A row for any queue item (library song or mixtape track) that plays its list when tapped.
struct PlayableQueueRow: View {
    let item: QueueItem
    let list: [QueueItem]
    var number: Int?
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        if case .library(let song) = item {
            PlayableSongRowItems(song: song, list: list, number: number)
        } else {
            Button { player.play(list, startAt: list.firstIndex(of: item) ?? 0) } label: {
                HStack(spacing: 12) {
                    if let number {
                        Text("\(number)").font(.serif(17)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 26)
                    } else {
                        QueueItemArtwork(item: item).frame(width: 46, height: 46)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 16)).lineLimit(1)
                        Text(item.artist).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "recordingtape").font(.caption).foregroundStyle(Palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A library song row inside a mixed list: plays the mixed list.
private struct PlayableSongRowItems: View {
    let song: Song
    let list: [QueueItem]
    var number: Int?
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        Button { player.play(list, startAt: list.firstIndex(of: .library(song)) ?? 0) } label: {
            SongRow(song: song, number: number, showArtwork: number == nil)
        }
        .buttonStyle(.plain)
        .modifier(SongContextMenu(song: song))
    }
}

/// Play / Shuffle for a mixed list.
struct PlayShuffleItemsRow: View {
    let items: [QueueItem]
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassPillButton(title: "Play", systemImage: "play.fill", prominent: true) { player.play(items) }
                GlassPillButton(title: "Shuffle", systemImage: "shuffle") { player.play(items, shuffled: true) }
            }
        }
        .disabled(items.isEmpty)
    }
}
