import SwiftData
import SwiftUI

/// Which records stand on the Listening Room's shelf, in order. Until you change it, it's your most played
/// albums; after that it's yours to fill with albums and mixtapes (kept in UserDefaults as record IDs).
@MainActor @Observable
final class RoomShelf {
    static let shared = RoomShelf()
    static let storageKey = "room.shelf"
    /// Your shelf as record IDs ("album-…", "mixtape-…"); nil until you change it.
    private(set) var ids: [String]?

    private init() { ids = UserDefaults.standard.stringArray(forKey: Self.storageKey) }

    /// The records on the shelf (each once, with your sides applied).
    func records(_ library: LibraryService, mixtapes: [Mixtape]) -> [VinylRecord] {
        let snap = library.snapshot
        guard let ids else {
            let played = library.stats.albums
            return (played.isEmpty ? library.recentlyAdded : played).prefix(14).map { VinylRecord.album($0, snap) }
        }
        var seen = Set<String>()
        return ids.compactMap { Self.record($0, snap, mixtapes) }.filter { seen.insert($0.id).inserted }
    }

    static func record(_ id: String, _ snap: LibrarySnapshot, _ mixtapes: [Mixtape]) -> VinylRecord? {
        if id.hasPrefix("album-"), let n = UInt64(id.dropFirst(6)), let album = snap.album(n) { return .album(album, snap) }
        if id.hasPrefix("mixtape-"), let m = mixtapes.first(where: { "mixtape-\($0.id)" == id }) { return .mixtape(m) }
        return nil
    }

    func set(_ ids: [String]) {
        self.ids = ids
        UserDefaults.standard.set(ids, forKey: Self.storageKey)
    }

    func remove(_ id: String, from current: [String]) { set(current.filter { $0 != id }) }

    /// Back to your most played albums.
    func reset() {
        ids = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}

/// Fill the shelf: what's on it (drag to reorder, swipe to take one off) and everything you could add, albums
/// and mixtapes, searchable.
struct ShelfPicker: View {
    let current: [VinylRecord]
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]
    @State private var shelf: [VinylRecord] = []
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if shelf.isEmpty { Text("Nothing on the shelf yet. Add records below.").foregroundStyle(Palette.secondary) }
                    ForEach(shelf) { r in row(r.title, r.artist) { RecordCover(record: r, cornerRadius: 4) } }
                        .onMove { shelf.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { shelf.remove(atOffsets: $0) }
                } header: { Text("On the shelf · \(shelf.count)") }
                Section("Add to the shelf") {
                    ForEach(mixtapeChoices) { m in
                        add { shelf.append(.mixtape(m)) } label: { row(m.title, "Mixtape · \(m.artist)") { RecordCover(record: .mixtape(m), cornerRadius: 4) } }
                    }
                    ForEach(albumChoices) { a in
                        add { shelf.append(.album(a, library.snapshot)) } label: { row(a.title, a.artist) { ArtworkView(albumID: a.id, cornerRadius: 4) } }
                    }
                }
            }
            .searchable(text: $search, prompt: "Albums and mixtapes")
            .navigationTitle("Your Shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { RoomShelf.shared.set(shelf.map(\.id)); dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .bottomBar) {
                    Button("Most Played Albums", systemImage: "arrow.uturn.backward") { RoomShelf.shared.reset(); dismiss() }
                }
            }
            .onAppear { if shelf.isEmpty { shelf = current } }
        }
    }

    private var onShelf: Set<String> { Set(shelf.map(\.id)) }

    private func matches(_ text: String...) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.contains { $0.localizedStandardContains(q) }
    }

    private var albumChoices: [Album] {
        let taken = onShelf
        return library.albums(.alphabetical).filter { !taken.contains("album-\($0.id)") && matches($0.title, $0.artist) }
    }

    private var mixtapeChoices: [Mixtape] {
        let taken = onShelf
        return mixtapes.filter { !taken.contains("mixtape-\($0.id)") && matches($0.title, $0.artist) }
    }

    private func add<L: View>(_ action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button {
            withAnimation(.liner) { action() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack {
                label()
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func row<A: View>(_ title: String, _ subtitle: String, @ViewBuilder art: () -> A) -> some View {
        HStack(spacing: 12) {
            art().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    ShelfPicker(current: PreviewData.snapshot.albums.prefix(3).map { .album($0, PreviewData.snapshot) })
        .environment(PreviewData.library).environment(PreviewData.player)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
