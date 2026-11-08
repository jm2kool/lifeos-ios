import SwiftData
import SwiftUI

/// MY EDITIONS (SPEC §6.7): pick the active edition of an album, create, edit or delete editions.
struct EditionsSheet: View {
    let subject: AlbumSubject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var editions: [Edition]
    @Query private var notes: [AlbumNote]
    @State private var editing: Edition?
    @AppStorage(AlbumTracklist.storageKey) private var savedOnlyAlbums = ""

    init(subject: AlbumSubject) {
        self.subject = subject
        let id = subject.id
        _editions = Query(filter: #Predicate<Edition> { $0.baseAlbumID == id }, sort: \Edition.createdAt)
        _notes = Query(filter: #Predicate<AlbumNote> { $0.albumID == id })
    }

    private var activeID: UUID? { notes.first?.activeEditionID }
    private var savedOnly: Bool { AlbumTracklist.savedOnly(subject.id, in: savedOnlyAlbums) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if subject.album != nil {
                        row(title: "Full Album", subtitle: "Every song on the album, from Apple Music", active: activeID == nil && !savedOnly) {
                            setTracklist(savedOnly: false)
                        }
                        row(title: "Saved Album", subtitle: "The \(subject.tracks.count) song\(subject.tracks.count == 1 ? "" : "s") in your library",
                            active: activeID == nil && savedOnly) { setTracklist(savedOnly: true) }
                    } else {
                        row(title: "Original", subtitle: "\(subject.tracks.count) songs", active: activeID == nil) { setActive(nil) }
                    }
                    ForEach(editions) { e in
                        row(title: e.title, subtitle: "\(e.tracks.count) songs", active: activeID == e.id) { setActive(e) }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(e) }
                                Button("Edit", systemImage: "pencil") { editing = e }.tint(.gray)
                            }
                    }
                } header: {
                    Text("My Editions").linerLabel()
                } footer: {
                    Text("Editions live only in \(AppBrand.name). Your Apple Music library is never modified.")
                }
                Section {
                    Button("+ Create New Edition") { create() }.font(.system(size: 15, weight: .semibold))
                }
            }
            .navigationTitle(subject.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .navigationDestination(item: $editing) { EditionEditor(edition: $0) }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.serif(18))
                    Text(subtitle).font(.caption).foregroundStyle(Palette.secondary)
                }
                Spacer()
                if active { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setTracklist(savedOnly: Bool) {
        savedOnlyAlbums = AlbumTracklist.setting(subject.id, savedOnly: savedOnly, in: savedOnlyAlbums)
        setActive(nil)
    }

    private func setActive(_ e: Edition?) {
        let note = Store.shared.albumNoteOrNew(subject.id, key: subject.key)
        note.activeEditionID = e?.id
        for ed in editions { ed.isActive = ed.id == e?.id }
        Store.shared.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func create() {
        let e = Edition(title: "My \(subject.title)", baseAlbumID: subject.id, tracks: subject.tracks.map(TrackResolver.reference))
        context.insert(e)
        Store.shared.save()
        editing = e
    }

    private func delete(_ e: Edition) {
        if activeID == e.id { setActive(nil) }
        if let f = e.motionCoverFile { try? FileManager.default.removeItem(at: MotionCoverFiles.url(f)) }
        context.delete(e)
        Store.shared.save()
    }
}

/// User motion covers live in Application Support/LINER/MotionCovers (not backed up; they can be re-attached).
enum MotionCoverFiles {
    static var folder: URL {
        var dir = URL.applicationSupportDirectory.appending(path: "LINER/MotionCovers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }
    static func url(_ name: String) -> URL { folder.appending(path: name) }
}
