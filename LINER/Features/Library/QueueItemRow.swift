import SwiftUI

/// A row for any queue item (library song or mixtape track) that plays its list when tapped.
struct PlayableQueueRow: View {
    let item: QueueItem
    let list: [QueueItem]
    var number: Int?
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.editionCover) private var edition

    var body: some View {
        if case .library(let song) = item {
            PlayableSongRowItems(song: song, list: list, number: number)
        } else {
            Button { player.play(list, startAt: list.firstIndex(of: item) ?? 0, edition: edition) } label: {
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
    @Environment(\.editionCover) private var edition

    var body: some View {
        Button { player.play(list, startAt: list.firstIndex(of: .library(song)) ?? 0, edition: edition) } label: {
            SongRow(song: song, number: number, showArtwork: number == nil)
        }
        .buttonStyle(.plain)
        .modifier(SongContextMenu(song: song))
    }
}

/// Play / Shuffle for a mixed list, with an optional circle on the right.
struct PlayShuffleItemsRow<Trailing: View>: View {
    let items: [QueueItem]
    @ViewBuilder var trailing: Trailing
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.editionCover) private var edition

    var body: some View {
        PlayShuffleIcons(play: { player.play(items, edition: edition) }, shuffle: { player.play(items, shuffled: true, edition: edition) }) { trailing }
            .disabled(items.isEmpty)
    }
}

extension PlayShuffleItemsRow where Trailing == EmptyView {
    init(items: [QueueItem]) { self.init(items: items) { EmptyView() } }
}
