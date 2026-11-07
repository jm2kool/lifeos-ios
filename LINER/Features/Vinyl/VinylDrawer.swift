import SwiftData
import SwiftUI

/// Home's record drawer handle (Vinyl Mode on): swipe up or tap to pull out the crate.
struct VinylDrawerHandle: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            VStack(spacing: 6) {
                Capsule().fill(Palette.faint).frame(width: 40, height: 5)
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Your crate").linerLabel(size: 10)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16).padding(.bottom, 6)
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < -20 { open = true } })
        .sheet(isPresented: $open) {
            CrateView().presentationDetents([.fraction(0.62), .large]).presentationBackground(.ultraThinMaterial)
        }
        .accessibilityLabel("Open your record crate")
    }
}

/// The crate: filter chips and a 3D flip-through of sleeves. Tap a sleeve to put it on the turntable.
struct CrateView: View {
    @Environment(LibraryService.self) private var library
    @Query(filter: #Predicate<AlbumNote> { $0.pinned }, sort: \AlbumNote.pinnedAt) private var pins: [AlbumNote]
    @Query(sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]
    @Query(sort: \MoodPlaylist.createdAt, order: .reverse) private var moods: [MoodPlaylist]
    @AppStorage("crate.filter") private var filter: CrateFilter = .recent
    @State private var visible: String?
    @State private var playing: VinylRecord?
    @Namespace private var sleeve

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The Crate").font(.serif(30)).padding(.horizontal, 20).padding(.top, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CrateFilter.allCases) { f in
                        Button(f.rawValue) { withAnimation(.liner) { filter = f } }
                            .font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(filter == f ? Color.black : Color.white)
                            .background(filter == f ? Color.white : Color.white.opacity(0.1), in: Capsule())
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            let list = records
            if list.isEmpty {
                EmptyStateView(symbol: "record.circle", title: "This crate is empty", message: "Try another filter.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: -70) {
                        ForEach(list) { r in
                            Button { playing = r } label: { SleeveView(record: r).frame(width: 230, height: 230) }
                                .buttonStyle(.plain)
                                .matchedTransitionSource(id: r.id, in: sleeve)
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .rotation3DEffect(.degrees(phase.value * -38), axis: (x: 0, y: 1, z: 0))
                                        .rotation3DEffect(.degrees(12), axis: (x: 1, y: 0, z: 0))
                                        .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                        .opacity(phase.isIdentity ? 1 : 0.75)
                                }
                                .id(r.id)
                                .accessibilityLabel("\(r.title) by \(r.artist)")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 80)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $visible)
                .sensoryFeedback(.selection, trigger: visible)
                .frame(height: 280)
                if let r = list.first(where: { $0.id == visible }) ?? list.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.serif(22)).lineLimit(1)
                        Text(r.artist).linerLabel(size: 10)
                    }
                    .padding(.horizontal, 20)
                }
            }
            Spacer()
        }
        .fullScreenCover(item: $playing) { r in
            TurntableView(record: r).navigationTransition(.zoom(sourceID: r.id, in: sleeve))
        }
    }

    private var records: [VinylRecord] {
        let snap = library.snapshot
        func album(_ a: Album) -> VinylRecord {
            VinylRecord(id: "album-\(a.id)", title: a.title, artist: a.artist, year: a.year, albumID: a.id, coverData: nil,
                        tracks: snap.songs(a.songIDs).map(QueueItem.library))
        }
        switch filter {
        case .pinned:
            return pins.compactMap { n in UInt64(n.albumID.dropFirst(6)).flatMap { snap.album($0) }.map(album) }
        case .recent: return library.recentlyAdded.prefix(30).map(album)
        case .mostPlayed: return library.stats.albums.prefix(30).map(album)
        case .mixtapes:
            return mixtapes.map { m in
                VinylRecord(id: "mixtape-\(m.id)", title: m.title, artist: m.artist, year: m.year, albumID: nil, coverData: m.coverImage,
                            tracks: m.orderedTracks.map { .local(TrackResolver.local($0)) })
            }
        case .moods:
            return moods.map { p in
                let songs = MoodPlaylistService.songs(p, library: library)
                return VinylRecord(id: "mood-\(p.id)", title: p.name, artist: "Mood playlist", year: nil, albumID: songs.first?.albumID,
                                   coverData: nil, tracks: songs.map(QueueItem.library))
            }
        }
    }
}

/// A record sleeve: the cover with a worn edge and a peek of black vinyl.
struct SleeveView: View {
    let record: VinylRecord
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.06)).padding(6).offset(x: 18)
            RecordCover(record: record, cornerRadius: 4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.6), radius: 14, x: 6, y: 10)
        }
    }
}

/// The record's art, from the library or a saved cover.
struct RecordCover: View {
    let record: VinylRecord
    var cornerRadius: CGFloat = 0
    var body: some View {
        if let data = record.coverData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            ArtworkView(albumID: record.albumID, cornerRadius: cornerRadius)
        }
    }
}
