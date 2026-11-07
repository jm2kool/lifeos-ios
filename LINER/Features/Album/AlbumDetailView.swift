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

    private var tracks: [QueueItem] {
        if let e = activeEdition { return TrackResolver.items(e.tracks, snapshot: library.snapshot) }
        return library.snapshot.songs(album.songIDs).map(QueueItem.library)
    }

    private var facts: String {
        let list = tracks
        var parts = [activeEdition == nil ? "ALBUM" : "EDITION", "\(list.count) SONG\(list.count == 1 ? "" : "S")",
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
                    Text(activeEdition?.title ?? album.title).font(.itemTitle).lineLimit(3)
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
                        PlayableQueueRow(item: item, list: list, number: activeEdition == nil ? (item.song?.trackNumber ?? i + 1) : i + 1)
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
        .background(Palette.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { AlbumActionsMenu(album: album) } label: { Label("More", systemImage: "ellipsis") }
            }
        }
    }

    private var editionSwitcher: some View {
        Menu {
            Button { setEdition(nil) } label: { checked("Original Album", activeEdition == nil) }
            ForEach(editions) { e in
                Button { setEdition(e) } label: { checked(e.title, activeEdition?.id == e.id) }
            }
            Divider()
            Button("Manage Editions", systemImage: "square.stack.3d.up") { passports.editions = .library(album, snapshot: library.snapshot) }
        } label: {
            HStack(spacing: 4) {
                Text(activeEdition?.title ?? "Original Album").linerLabel(size: 10)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.label)
            }
        }
        .accessibilityLabel("Edition: \(activeEdition?.title ?? "Original Album")")
    }

    @ViewBuilder private func checked(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func setEdition(_ e: Edition?) {
        let note = Store.shared.albumNoteOrNew("album-\(album.id)", key: album.key)
        note.activeEditionID = e?.id
        for ed in editions { ed.isActive = ed.id == e?.id }
        Store.shared.save()
    }

    private func actions(_ list: [QueueItem]) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                PlayShuffleItemsRow(items: list)
                GlassCircleButton(systemImage: "arrow.down.circle", label: "Download in Music") { openInMusic() }
                AlbumPassportButton(album: album)
            }
        }
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

/// The album header: edition cover, your cover override, a motion cover, or the album artwork.
struct AlbumHeaderArt: View {
    let albumID: UInt64
    let note: AlbumNote?
    let edition: Edition?

    var body: some View {
        let motion = edition?.motionCoverFile ?? note?.motionCoverFile
        let still = edition?.coverImage ?? note?.coverOverride
        ZStack {
            if let data = still, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ArtworkView(albumID: albumID, cornerRadius: 0)
            }
            if let motion { LoopingVideo(url: MotionCoverFiles.url(motion)) }
        }
    }
}

#Preview {
    NavigationStack { AlbumDetailView(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
