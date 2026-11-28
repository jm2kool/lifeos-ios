import SwiftData
import SwiftUI

/// An album (SPEC §6.4): full-bleed cover (motion cover if attached), serif title, glass actions, facts,
/// edition switcher, tracklist, listening history and your top 3 songs. The cover stays still (unless Studio gives
/// it motion or a video) and fades out by the title into one solid colour from it, like the old Music app, with the
/// tracklist in the cover's colours; Studio and Customise Album change everything else about it.
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
    @State private var headerHeight: CGFloat = 400
    @State private var scrolled = 0.0
    @State private var coverColor = Color.white
    @State private var djMix = false
    /// The page's colour and the tracklist's colours, picked from the cover on show (like the old Music app).
    @State private var picked: AlbumColours?
    @AppStorage(AlbumPalette.settingKey) private var colouredTracklists = true
    @AppStorage(AlbumText.titleKey) private var titleScale = 1.0

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
    private var lookKey: String { LookKey.album(album.id) }
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
        if activeEdition == nil, album.editionIDs.count > 1 { parts.append("\(album.editionIDs.count) EDITIONS") }
        if !album.genre.isEmpty { parts.append(album.genre.uppercased()) }
        return parts.joined(separator: " · ")
    }

    /// The one colour the page takes below the cover: the cover's (or the one you chose in Studio).
    private var pageColour: Color {
        picked.map { studio.colours(from: $0).background } ?? studio.background.map(Color.init(hex:)) ?? Palette.background
    }

    /// Your Studio look for this album (the plain album when you haven't made one).
    private var studio: StudioLook { StudioStore.shared.look(album.id) ?? StudioLook() }

    /// The tracklist colours, or nil for plain white (Settings → Covers → Coloured tracklists, or Studio).
    private var tint: AlbumColours? {
        _ = colouredTracklists
        return picked.flatMap { studio.shownColours($0) }
    }

    var body: some View {
        let list = tracks
        let look = studio
        let tint = tint
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CoverHeader(lookKey: lookKey, backdrop: .album(album.id), coverColor: coverColor, scrolled: scrolled, height: $headerHeight,
                            fadeColour: pageColour) {
                    AlbumHeaderArt(albumID: album.id, note: notes.first, edition: activeEdition, motion: look.motion) { img, key in
                        Task {
                            let found = await AlbumPalette.colours(for: img, key: "\(key)-page")
                            withAnimation(.easeInOut(duration: 0.5)) { picked = found }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let edition = activeEdition {
                        Text(edition.title).albumFace(30 * titleScale, fallback: .serif(30 * titleScale)).lineLimit(3)
                    } else {
                        AlbumLogoTitle(lookKey: lookKey, albumID: album.id, title: album.title, maxWidth: 300 * titleScale, maxHeight: 110 * titleScale,
                                       font: .serif(30 * titleScale), fontSize: 30 * titleScale, coverColor: coverColor, skipPlaced: true)
                    }
                    if let artist = library.snapshot.artist(named: album.artist) {
                        NavigationLink(value: artist) { Text(album.artist).linerLabel(size: 12 * titleScale) }.buttonStyle(.plain)
                    } else {
                        Text(album.artist).linerLabel(size: 12 * titleScale)
                    }
                    actions(list).padding(.top, 10).environment(\.albumColours, tint)
                    Text(facts).linerLabel(size: 10 * titleScale).padding(.top, 8)
                    editionSwitcher.padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.top, -24)

                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                        PlayableQueueRow(item: item, list: list, number: trackNumbersLookRight(list) ? (item.song?.trackNumber ?? i + 1) : i + 1)
                            .padding(.vertical, 10)
                        Divider().overlay(tint.map { $0.primary.opacity(0.16) } ?? Palette.stroke)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18)
                .albumTextSizes()
                .environment(\.albumColours, tint)

                if let date = library.snapshot.songs(album.songIDs).compactMap(\.releaseDate).first {
                    Text("Released \(date.formatted(date: .long, time: .omitted))")
                        .font(.footnote).foregroundStyle(Palette.label).padding(16)
                }
                AlbumHistory(album: album, songs: library.snapshot.songs(album.songIDs)).padding(.horizontal, 16).padding(.top, 8)
                OtherEditionsShelf(title: album.title, artist: album.artist, excludingName: album.title).padding(.top, 28)
            }
            .padding(.bottom, 32)
        }
        .headerScrollProgress(headerHeight: headerHeight, progress: $scrolled)
        .environment(\.albumFace, LookStore.shared.look(lookKey).face)
        .environment(\.albumArtist, album.artist)
        .environment(\.mixContext, lookKey)
        .sheet(isPresented: $djMix) { MixEditorView(context: lookKey, title: album.title, items: list) }
        .environment(\.editionCover, activeEdition.map { EditionCover(editionID: $0.id, itemIDs: Set(list.map(\.id))) })
        // Below the cover, the page is one solid colour from it.
        .background(pageColour.ignoresSafeArea())
        .environment(\.onArt, picked != nil)
        .ignoresSafeArea(edges: .top)
        .task(id: album.id) { coverColor = await CoverColor.dominant(.album(album.id)) }
        .task(id: album.id) {
            let ids = library.snapshot.songs(album.songIDs).filter(\.hasStoreID).map(\.storeID)
            guard !ids.isEmpty else { return }
            catalog = await AppleCatalog.fullAlbum(songStoreIDs: ids)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavBarLogo(lookKey: lookKey, albumID: album.id, title: activeEdition?.title ?? album.title, visible: scrolled)
                    .environment(\.albumFace, LookStore.shared.look(lookKey).face)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Studio", systemImage: "paintbrush.pointed") { passports.studio = album }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    AlbumActionsMenu(album: album)
                    Button(MixStore.shared.hasMix(lookKey) ? "Edit DJ Mix" : "DJ Mix", systemImage: "dial.medium") { djMix = true }
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
            Button("Edit in Studio", systemImage: "paintbrush.pointed") { passports.studio = album }
            Button("Customise Album", systemImage: "slider.horizontal.3") { passports.customise = album }
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

#Preview {
    NavigationStack { AlbumDetailView(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
