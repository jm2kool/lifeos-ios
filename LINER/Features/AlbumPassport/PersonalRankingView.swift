import SwiftUI

/// Drag the album's songs into your own order (SPEC §6.8: "Your order, not your play counts").
struct PersonalRankingView: View {
    let subject: AlbumSubject
    @Bindable var note: AlbumNote
    @State private var order: [QueueItem] = []

    var body: some View {
        List {
            Section {
                ForEach(Array(order.enumerated()), id: \.element.id) { i, item in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.serif(22)).monospacedDigit().foregroundStyle(i < 3 ? .white : Palette.label).frame(width: 34)
                        QueueItemArtwork(item: item).frame(width: 40, height: 40)
                        Text(item.title).lineLimit(1)
                    }
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    note.personalRanking = order.map(\.id)
                }
            } footer: {
                Text("Your order, not your play counts.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .sensoryFeedback(.selection, trigger: note.personalRanking)
        .navigationTitle("Personal Ranking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { order = subject.tracks; note.personalRanking = [] }
            }
        }
        .onAppear { order = Self.ordered(subject.tracks, by: note.personalRanking) }
    }

    /// Saved order first (skipping songs that left the album), then any new songs in album order.
    static func ordered(_ tracks: [QueueItem], by ids: [String]) -> [QueueItem] {
        guard !ids.isEmpty else { return tracks }
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ranked = ids.compactMap { byID[$0] }
        return ranked + tracks.filter { !ids.contains($0.id) }
    }
}
