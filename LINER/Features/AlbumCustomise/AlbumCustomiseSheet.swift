import PhotosUI
import SwiftData
import SwiftUI

/// Customise Album: everything you can change about an album in one place — text sizes, logo, font and cover
/// layout, which tracklist or edition plays, the cover and motion cover, the title lettering, and its pin on Home
/// (and the pin's cover) — with a live preview.
struct AlbumCustomiseSheet: View {
    let album: Album
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AlbumCustomiseForm(album: album)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
    }
}

/// The Customise Album form itself (also pushed from the Album Passport).
struct AlbumCustomiseForm: View {
    let album: Album
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Query private var notes: [AlbumNote]
    @Query private var editions: [Edition]
    @AppStorage(AlbumTracklist.storageKey) private var savedOnlyAlbums = ""
    @AppStorage(AlbumText.plainTitlesKey) private var plainTitles = ""
    @AppStorage(AlbumText.titleKey) private var titleScale = 1.0
    @AppStorage("albumLogos") private var albumLogos = true
    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var working = false
    @State private var managingEditions = false
    /// The logo, font or pin cover editor open over this sheet.
    @State private var lookRequest: LookRequest?

    init(album: Album) {
        self.album = album
        let id = "album-\(album.id)"
        _notes = Query(filter: #Predicate<AlbumNote> { $0.albumID == id })
        _editions = Query(filter: #Predicate<Edition> { $0.baseAlbumID == id }, sort: \Edition.createdAt)
    }

    private var subjectID: String { "album-\(album.id)" }
    private var lookKey: String { LookKey.album(album.id) }
    private var note: AlbumNote? { notes.first }

    /// Which tracklist plays: the full album, only your saved songs, or one of your editions.
    private enum Choice: Hashable { case full, saved, edition(UUID) }

    private var choice: Binding<Choice> {
        Binding {
            if let id = note?.activeEditionID, editions.contains(where: { $0.id == id }) { return .edition(id) }
            return AlbumTracklist.savedOnly(subjectID, in: savedOnlyAlbums) ? .saved : .full
        } set: { new in
            switch new {
            case .full, .saved:
                savedOnlyAlbums = AlbumTracklist.setting(subjectID, savedOnly: new == .saved, in: savedOnlyAlbums)
                setEdition(nil)
            case .edition(let id):
                setEdition(id)
            }
        }
    }

    var body: some View {
        Form {
            Section { preview }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            Section {
                AlbumTextSizeRows()
            } header: { Text("Text size") } footer: {
                Text("Sizes apply to every album, release, playlist and mixtape page.")
            }
            styleSection
            Section("Tracklist") {
                Picker("Plays", selection: choice) {
                    Text("Full Album").tag(Choice.full)
                    Text("Saved Album · \(album.songIDs.count) song\(album.songIDs.count == 1 ? "" : "s")").tag(Choice.saved)
                    ForEach(editions) { e in Text(e.title).tag(Choice.edition(e.id)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Button("Manage Editions", systemImage: "square.stack.3d.up") { managingEditions = true }
            }
            coverSection
            Section {
                Toggle("Lettering from the cover", isOn: lettering).disabled(!albumLogos)
            } header: { Text("Title") } footer: {
                Text(albumLogos ? "Off shows the album's name in plain type." : "Album title logos are off in Settings → Covers.")
            }
            Section("Home") {
                Toggle("Pin to Home", isOn: Binding(get: { note?.pinned ?? false }, set: { on in
                    if on != (note?.pinned ?? false) { Store.shared.togglePin(albumID: subjectID, key: album.key) }
                }))
                if note?.pinned == true {
                    Picker("Pinned look", selection: Binding(get: { note?.pinnedAppearance ?? .artistPortrait }, set: {
                        Store.shared.setAppearance($0, albumID: subjectID, key: album.key)
                    })) {
                        ForEach(PinAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Button("Choose Pin Cover…", systemImage: "photo.stack") {
                        Store.shared.setAppearance(.albumArtwork, albumID: subjectID, key: album.key)
                        lookRequest = .album(.pinCover, album, snapshot: library.snapshot)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Customise Album")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $managingEditions) { EditionsSheet(subject: .library(album, snapshot: library.snapshot)) }
        .sheet(item: $lookRequest) { LookSheet(request: $0) }
        .onChange(of: photo) { _, p in Task { await save(p, motion: false) } }
        .onChange(of: video) { _, v in Task { await save(v, motion: true) } }
    }

    /// How the page will look: the cover, the title and the first songs at the chosen sizes.
    private var preview: some View {
        let songs = Array(library.snapshot.songs(album.songIDs).prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                ArtworkView(albumID: album.id, cornerRadius: 10).frame(width: 72, height: 72)
                AlbumLogoTitle(lookKey: lookKey, albumID: album.id, title: album.title, maxWidth: 220 * titleScale, maxHeight: 80 * titleScale,
                               font: .serif(30 * titleScale), fontSize: 30 * titleScale)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in SongRow(song: s, number: s.trackNumber > 0 ? s.trackNumber : i + 1) }
        }
        .albumTextSizes()
        .environment(\.albumFace, LookStore.shared.look(lookKey).face)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
        .animation(.liner, value: titleScale)
    }

    /// Logo, font and how the cover sits at the top of the page.
    private var styleSection: some View {
        let store = LookStore.shared
        let look = store.look(lookKey)
        return Section("Style") {
            Button(store.logo(lookKey) == nil ? "Add Logo…" : "Edit Logo…", systemImage: "signature") {
                lookRequest = .album(.logo, album, snapshot: library.snapshot)
            }
            Button(look.face == nil ? "Choose Font…" : "Font: \(look.face?.family ?? "")", systemImage: "textformat") {
                lookRequest = .album(.font, album, snapshot: library.snapshot)
            }
            Picker("Cover", selection: Binding(get: { look.layout ?? .full }, set: { new in
                withAnimation(.liner) { store.update(lookKey) { $0.layout = new == .full ? nil : new } }
            })) {
                Text("Full screen").tag(CoverLayout.full)
                Text("Square").tag(CoverLayout.square)
            }
        }
    }

    private var coverSection: some View {
        Section {
            PhotosPicker(selection: $photo, matching: .images) { Label("Choose cover photo", systemImage: "photo") }
            PhotosPicker(selection: $video, matching: .any(of: [.videos, .images])) { Label("Choose motion cover", systemImage: "play.rectangle") }
            if working { ProgressView("Preparing motion cover…") }
            if CoverOverrides.shared.image(album.id) != nil || note?.motionCoverFile != nil {
                Button("Use original artwork", systemImage: "arrow.uturn.backward", role: .destructive) { CoverSaver.reset(album) }
            }
        } header: { Text("Cover") } footer: {
            Text("Motion covers loop on the album page, behind the player and on the Lock Screen. Your Apple Music library is never changed.")
        }
    }

    /// Plain titles are kept as the same comma-separated id list `AlbumTracklist` uses.
    private var lettering: Binding<Bool> {
        Binding {
            !AlbumTracklist.savedOnly(subjectID, in: plainTitles)
        } set: { on in
            plainTitles = AlbumTracklist.setting(subjectID, savedOnly: !on, in: plainTitles)
        }
    }

    private func setEdition(_ id: UUID?) {
        let note = Store.shared.albumNoteOrNew(subjectID, key: album.key)
        note.activeEditionID = id
        for e in editions { e.isActive = e.id == id }
        Store.shared.save()
    }

    private func save(_ item: PhotosPickerItem?, motion: Bool) async {
        guard let item else { return }
        if motion { working = true }
        defer { working = false }
        await CoverSaver.save(item, for: CoverRequest(album: album, motion: motion))
        player.notice = motion ? "Motion cover set for “\(album.title)”." : "Cover set for “\(album.title)”."
        if motion { video = nil } else { photo = nil }
    }
}

#Preview {
    AlbumCustomiseSheet(album: PreviewData.snapshot.albums[0])
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
