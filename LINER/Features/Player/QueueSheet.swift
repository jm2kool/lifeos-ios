import SwiftUI

/// Up Next: reorder by dragging, swipe to remove, tap to jump.
struct QueueSheet: View {
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        NavigationStack {
            List {
                if let now = player.current {
                    Section("Now playing") { row(now) }
                }
                Section("Up next") {
                    if player.upNext.isEmpty {
                        Text("Nothing queued.").foregroundStyle(Palette.secondary)
                    }
                    ForEach(Array(player.upNext.enumerated()), id: \.offset) { offset, item in
                        Button { player.jump(to: player.index + 1 + offset) } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                    .onMove { player.moveUpNext(from: $0, to: $1) }
                    .onDelete { player.removeUpNext(at: $0) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: player.queue.count)
        }
    }

    private func row(_ item: QueueItem) -> some View {
        HStack(spacing: 12) {
            QueueItemArtwork(item: item).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                Text(item.artist).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer()
            if !item.isLibrary { Image(systemName: "recordingtape").font(.caption).foregroundStyle(Palette.faint) }
        }
    }
}
