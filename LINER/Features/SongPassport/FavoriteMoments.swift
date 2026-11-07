import SwiftUI

/// Favourite moments: type a time or take the current one, name it, tap to jump there.
struct FavoriteMoments: View {
    let item: QueueItem
    @Bindable var note: SongNote
    @Environment(PlaybackCoordinator.self) private var player
    @State private var time = ""
    @State private var name = ""

    private var isPlayingThis: Bool { player.current?.id == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(note.moments) { m in
                Button { jump(m.seconds) } label: {
                    HStack {
                        Text(m.seconds.trackTime).font(.serif(18)).monospacedDigit()
                        Text(m.name.isEmpty ? "Moment" : m.name).foregroundStyle(Palette.secondary)
                        Spacer()
                        Image(systemName: "play.circle")
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { note.moments.removeAll { $0.id == m.id } }
                }
            }
            HStack(spacing: 8) {
                TextField("1:23", text: $time).keyboardType(.numbersAndPunctuation).frame(width: 64)
                TextField("Name (optional)", text: $name)
                Button("Add") { add() }.disabled(Self.parse(time) == nil)
            }
            .textFieldStyle(.roundedBorder)
            if isPlayingThis {
                Button("Use current time", systemImage: "clock") { time = player.currentTime.trackTime }.font(.footnote)
            }
        }
    }

    private func add() {
        guard let s = Self.parse(time) else { return }
        note.moments.append(Moment(seconds: s, name: name.trimmingCharacters(in: .whitespaces)))
        time = ""
        name = ""
    }

    private func jump(_ seconds: Double) {
        if isPlayingThis { player.seek(to: seconds); return }
        player.play([item])
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            player.seek(to: seconds)
        }
    }

    /// "83", "1:23" or "1:02:03" → seconds.
    static func parse(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}

/// Share button for the Song Passport.
@MainActor
enum SongPassportShare {
    @ViewBuilder static func button(item: QueueItem) -> some View {
        ShareCardButton { .song(item, note: Store.shared.songNote(item.id), plays: item.song?.playCount) }
    }
}
