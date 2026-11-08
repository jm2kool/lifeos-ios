import SwiftData
import SwiftUI

/// An album (SPEC §6.4): full-bleed cover (motion cover if attached), serif title, glass actions, facts,
/// edition switcher, tracklist, listening history and your top 3 songs.
struct AlbumDetailView: View {
    let album: Album
    @Environment(LibraryService.self) private var library
    @Environment(PassportPresenter.self) private var passports
    @Environment(\.openURL) private var openURL
    @Query private var notes: [AlbumNote]
    @Query private var editions: [Edition]
    @AppStorage(AlbumTracklist.storageKey) private var savedOnlyAlbums = ""
    /// The album as Apple Music lists it (nil until fetched, or when Apple doesn't know it).
    @State private var catalog: [AppleCatalog.Track]?

    init(album: Album) {
        self.album = album
        let id = "album-\(album.id)"
        _notes = Query(filter: #Predicate<AlbumNote> { $0.albumID == id })
        _editions = Query(filter: #Predicate<Edition> { $0.baseAlbumID == id }, sort: \Edition.createdAt)
    }

    private var activeEdition: Edition? {
        guard let id = notes.first?.activeEditionID else { return nil }
        return editions.first { $0.id == id }
    }

    private var subjectID: String { "album-\(album.id)" }
    private var savedOnly: Bool { AlbumTracklist.savedOnly(subjectID, in: savedOnlyAlbums) }
    private var saved: [QueueItem] { library.snapshot.songs(album.songIDs).map(QueueItem.library) }

    /// Every song on the album: yours where you have them, the rest streamed from Apple Music.
    private var full: [QueueItem]? {
        guard let catalog, catalog.count >= album.songIDs.count else { return nil }
        let mine = library.snapshot.songsByStoreID
        return catalog.map { .library($0.song(in: library.snapshot, byStoreID: mine)) }
    }

    private var tracks: [QueueItem] {
        if let e = activeEdition { return TrackResolver.items(e.tracks, snapshot: library.snapshot) }
        if !savedOnly, let full { return full }
        return saved
    }

    private var tracklistName: String {
        if let e = activeEdition { return e.title }
        if savedOnly { return "Saved Album" }
        return full == nil ? "Album" : "Full Album"
    }

    private var facts: String {
        let list = tracks
        var parts = [activeEdition != nil ? "EDITION" : (savedOnly && full != nil ? "SAVED" : "ALBUM"), "\(list.count) SONG\(list.count == 1 ? "" : "S")",
                     list.reduce(0) { $0 + $1.duration }.minutesLabel]
        if !album.genre.isEmpty { parts.append(album.genre.uppercased()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let list = tracks
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    AlbumHeaderArt(albumID: album.id, note: notes.first, edition: activeEdition)
                        .aspectRatio(1, contentMode: .fit).clipped()
                    LinearGradient(colors: [.clear, .black], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let edition = activeEdition {
                        Text(edition.title).font(.itemTitle).lineLimit(3)
                    } else {
                        AlbumTitle(albumID: album.id, title: album.title)
                    }
                    if let artist = library.snapshot.artist(named: album.artist) {
                        NavigationLink(value: artist) { Text(album.artist).linerLabel(size: 12) }.buttonStyle(.plain)
                    } else {
                        Text(album.artist).linerLabel(size: 12)
                    }
                    actions(list).padding(.top, 10)
                    Text(facts).linerLabel(size: 10).padding(.top, 8)
                    editionSwitcher.padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.top, -24)

                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                        PlayableQueueRow(item: item, list: list, number: trackNumbersLookRight(list) ? (item.song?.trackNumber ?? i + 1) : i + 1)
                            .padding(.vertical, 10)
                        Divider().overlay(Palette.stroke)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18)

                if let date = library.snapshot.songs(album.songIDs).compactMap(\.releaseDate).first {
                    Text("Released \(date.formatted(date: .long, time: .omitted))")
                        .font(.footnote).foregroundStyle(Palette.label).padding(16)
                }
                AlbumHistory(album: album, songs: library.snapshot.songs(album.songIDs)).padding(.horizontal, 16).padding(.top, 8)
            }
            .padding(.bottom, 32)
        }
        .environment(\.editionCover, activeEdition.map { EditionCover(editionID: $0.id, itemIDs: Set(list.map(\.id))) })
        .background(Palette.background)
        .ignoresSafeArea(edges: .top)
        .task(id: album.id) {
            let ids = library.snapshot.songs(album.songIDs).filter(\.hasStoreID).map(\.storeID)
            guard !ids.isEmpty else { return }
            catalog = await AppleCatalog.fullAlbum(songStoreIDs: ids)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    AlbumActionsMenu(album: album)
                    Button("Download in Music", systemImage: "arrow.down.circle") { openInMusic() }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
    }

    /// Use the album's own track numbers only when they run 1, 2, 3… (an EP of later tracks would show "2").
    private func trackNumbersLookRight(_ list: [QueueItem]) -> Bool {
        guard activeEdition == nil else { return false }
        let numbers = list.compactMap { $0.song?.trackNumber }
        return numbers.count == list.count && numbers.first == 1 && Set(numbers).count == numbers.count
    }

    private var editionSwitcher: some View {
        Menu {
            Button { setTracklist(savedOnly: false) } label: {
                checked(full.map { "Full Album · \($0.count) songs" } ?? "Full Album", activeEdition == nil && !savedOnly)
            }
            .disabled(full == nil && catalog != nil)
            Button { setTracklist(savedOnly: true) } label: {
                checked("Saved Album · \(album.songIDs.count) song\(album.songIDs.count == 1 ? "" : "s")", activeEdition == nil && savedOnly)
            }
            ForEach(editions) { e in
                Button { setEdition(e) } label: { checked(e.title, activeEdition?.id == e.id) }
            }
            Divider()
            Button("Manage Editions", systemImage: "square.stack.3d.up") { passports.editions = .library(album, snapshot: library.snapshot) }
        } label: {
            HStack(spacing: 4) {
                Text(tracklistName).linerLabel(size: 10)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.label)
            }
        }
        .accessibilityLabel("Edition: \(tracklistName)")
    }

    @ViewBuilder private func checked(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    /// Full Album or Saved Album (and back off any edition).
    private func setTracklist(savedOnly: Bool) {
        savedOnlyAlbums = AlbumTracklist.setting(subjectID, savedOnly: savedOnly, in: savedOnlyAlbums)
        if activeEdition != nil { setEdition(nil) }
    }

    private func setEdition(_ e: Edition?) {
        let note = Store.shared.albumNoteOrNew("album-\(album.id)", key: album.key)
        note.activeEditionID = e?.id
        for ed in editions { ed.isActive = ed.id == e?.id }
        Store.shared.save()
    }

    private func actions(_ list: [QueueItem]) -> some View {
        PlayShuffleItemsRow(items: list) { AlbumPassportButton(album: album) }
    }

    /// A third-party app can't download, so this opens the album in the Music app to download there.
    private func openInMusic() {
        let songs = library.snapshot.songs(album.songIDs)
        if let id = songs.first(where: { !$0.storeID.isEmpty && $0.storeID != "0" })?.storeID,
           let url = URL(string: "https://music.apple.com/song/\(id)") {
            openURL(url)
        } else if let url = URL(string: "music://") {
            openURL(url)
        }
    }
}

/// The album header: a motion cover if you attached one; otherwise the cover (edition cover, your own cover,
/// or the album artwork) as a moving Living Cover while you're on the page.
struct AlbumHeaderArt: View {
    let albumID: UInt64
    let note: AlbumNote?
    let edition: Edition?
    @State private var image: UIImage?
    @State private var look = ArtworkLook.neutral

    private var stillKey: String {
        "album-\(albumID)\(CoverVersions.suffix(albumID))-\(edition?.id.uuidString ?? "")-\(edition?.coverImage?.count ?? 0)"
    }

    var body: some View {
        let motion = edition?.motionCoverFile ?? note?.motionCoverFile
        ZStack {
            ArtworkView(albumID: albumID, cornerRadius: 0)
            if let motion {
                LoopingVideo(url: MotionCoverFiles.url(motion))
            } else if let image, MotionSettings.livingCoversOn {
                LivingCoverView(image: image, look: look, key: stillKey).transition(.opacity)
            }
        }
        .task(id: stillKey) {
            var img: UIImage?
            if let data = edition?.coverImage { img = UIImage(data: data) }
            if img == nil { img = CoverOverrides.shared.image(albumID) }
            if img == nil { img = await ArtworkCache.shared.image(album: albumID, pixels: 1400) }
            guard let img else { return }
            look = await ArtworkAnalysis.look(for: img, key: stillKey)
            withAnimation(.easeIn(duration: 0.4)) { image = img }
        }
    }
}

#Preview {
    NavigationStack { AlbumDetailView(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
