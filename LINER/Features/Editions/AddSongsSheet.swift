import SwiftData
import SwiftUI

/// Pick songs from your library or your mixtapes to add to an edition.
struct AddSongsSheet: View {
    let onAdd: ([QueueItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryService.self) private var library
    @Query(sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]
    @State private var source = 0
    @State private var query = ""
    @State private var picked: [QueueItem] = []

    var body: some View {
        NavigationStack {
            List {
                Picker("Source", selection: $source) {
                    Text("Library").tag(0)
                    Text("Mixtapes").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                ForEach(candidates) { item in
                    Button { toggle(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: picked.contains(item) ? "checkmark.circle.fill" : "circle")
                            QueueItemArtwork(item: item).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).lineLimit(1)
                                Text("\(item.artist) · \(item.albumTitle)").font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if source == 1 && mixtapes.isEmpty {
                    Text("No mixtapes yet. Import audio in Library → Mixtapes.").foregroundStyle(Palette.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(picked.count)") { onAdd(picked); dismiss() }.disabled(picked.isEmpty)
                }
            }
        }
    }

    private var candidates: [QueueItem] {
        if source == 1 {
            let all = mixtapes.flatMap { $0.orderedTracks.map { QueueItem.local(TrackResolver.local($0)) } }
            return query.isEmpty ? all : all.filter { $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }
        }
        let songs = query.isEmpty ? library.songs(.mostPlayed).prefix(150).map { $0 }
            : library.snapshot.songs.filter { $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }.prefix(150).map { $0 }
        return songs.map(QueueItem.library)
    }

    private func toggle(_ item: QueueItem) {
        if let i = picked.firstIndex(of: item) { picked.remove(at: i) } else { picked.append(item) }
    }
}
