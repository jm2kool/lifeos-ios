import SwiftData
import SwiftUI

/// The crate (full screen): flip through sleeves in 3D, the backdrop takes the colours of the record in front,
/// and "Put it on" carries it to the turntable. Swipe down or ✕ to put the crate away.
struct CrateView: View {
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<AlbumNote> { $0.pinned }, sort: \AlbumNote.pinnedAt) private var pins: [AlbumNote]
    @Query(sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]
    @Query(sort: \MoodPlaylist.createdAt, order: .reverse) private var moods: [MoodPlaylist]
    @AppStorage("crate.filter") private var filter: CrateFilter = .recent
    @AppStorage("vinylMode") private var vinylMode = false
    @State private var focused: String?
    @State private var playing: VinylRecord?
    @State private var backdrop: UIImage?
    @Namespace private var sleeve

    var body: some View {
        let list = records
        let current = list.first { $0.id == focused } ?? list.first
        GeometryReader { geo in
            let side = min(geo.size.width * 0.72, 320)
            ZStack {
                background
                VStack(spacing: 0) {
                    header.padding(.horizontal, 20).padding(.top, 8)
                    chips.padding(.top, 14)
                    Spacer(minLength: 10)
                    if list.isEmpty {
                        EmptyStateView(symbol: "record.circle", title: "This crate is empty", message: "Try another filter.")
                    } else {
                        flipThrough(list, side: side, width: geo.size.width)
                        if let r = current { details(r).padding(.top, 8) }
                    }
                    Spacer(minLength: 20)
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { if $0.translation.height > 160 && abs($0.translation.width) < 80 { dismiss() } })
        .task(id: current?.id) { await loadBackdrop(current) }
        .fullScreenCover(item: $playing) { r in
            TurntableView(record: r).navigationTransition(.zoom(sourceID: r.id, in: sleeve))
        }
        .statusBarHidden()
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            Color.black
            if let backdrop {
                FillImage(image: backdrop).blur(radius: 70).opacity(0.5).scaleEffect(1.4)
                    .transition(.opacity).id(backdrop)
            }
            RadialGradient(colors: [.clear, .black.opacity(0.85)], center: .center, startRadius: 120, endRadius: 520)
            LinearGradient(colors: [.black.opacity(0.6), .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: backdrop)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("The Crate").font(.serif(34))
                Text("Vinyl Mode").linerLabel(size: 10)
            }
            Spacer()
            Toggle("Vinyl Mode", isOn: $vinylMode).labelsHidden()
                .accessibilityLabel("Vinyl Mode")
            GlassCircleButton(systemImage: "xmark", label: "Close the crate", size: 44) { dismiss() }
                .padding(.leading, 8)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CrateFilter.allCases) { f in
                    Button(f.rawValue) { withAnimation(.liner) { filter = f; focused = nil } }
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(filter == f ? Color.black : Color.white)
                        .background(filter == f ? Color.white : Color.white.opacity(0.1), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func flipThrough(_ list: [VinylRecord], side: CGFloat, width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: -side * 0.28) {
                ForEach(list) { r in
                    let isFront = r.id == (focused ?? list.first?.id)
                    Button { playing = r } label: {
                        VStack(spacing: 6) {
                            SleeveView(record: r, peek: isFront ? 0.32 : 0.12).frame(width: side, height: side)
                            // A soft reflection on the floor.
                            RecordCover(record: r, cornerRadius: 4).frame(width: side, height: side * 0.35, alignment: .top).clipped()
                                .scaleEffect(x: 1, y: -1).opacity(0.18).blur(radius: 2)
                                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: r.id, in: sleeve)
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .rotation3DEffect(.degrees(phase.value * -42), axis: (x: 0, y: 1, z: 0))
                            .scaleEffect(phase.isIdentity ? 1 : 0.84)
                            .opacity(phase.isIdentity ? 1 : 0.7)
                    }
                    .zIndex(isFront ? 1 : 0)
                    .id(r.id)
                    .accessibilityLabel("\(r.title) by \(r.artist)")
                    .accessibilityHint("Double-tap to put it on the turntable")
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, max(0, (width - side) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focused)
        .sensoryFeedback(.selection, trigger: focused)
        .frame(height: side * 1.45)
    }

    private func details(_ r: VinylRecord) -> some View {
        VStack(spacing: 6) {
            Text(r.title).font(.serif(26)).lineLimit(1).padding(.horizontal, 24)
            Text([r.artist, r.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")).linerLabel(size: 10)
            Button { playing = r } label: {
                Label("Put it on", systemImage: "record.circle").font(.system(size: 17, weight: .bold)).frame(width: 190, height: 52)
            }
            .buttonStyle(.linerPrimary).buttonBorderShape(.capsule)
            .padding(.top, 14)
        }
        .id(r.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: r.id)
    }

    private func loadBackdrop(_ r: VinylRecord?) async {
        guard let r else { return }
        if let data = r.coverData { backdrop = UIImage(data: data); return }
        if let id = r.albumID { backdrop = CoverOverrides.shared.image(id) ?? (await ArtworkCache.shared.image(album: id, pixels: 320)) }
    }

    private var records: [VinylRecord] {
        let snap = library.snapshot
        switch filter {
        case .pinned:
            return pins.compactMap { n in UInt64(n.albumID.dropFirst(6)).flatMap { snap.album($0) }.map { VinylRecord.album($0, snap) } }
        case .recent: return library.recentlyAdded.prefix(30).map { VinylRecord.album($0, snap) }
        case .mostPlayed: return library.stats.albums.prefix(30).map { VinylRecord.album($0, snap) }
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

extension VinylRecord {
    static func album(_ a: Album, _ snap: LibrarySnapshot) -> VinylRecord {
        VinylRecord(id: "album-\(a.id)", title: a.title, artist: a.artist, year: a.year, albumID: a.id, coverData: nil,
                    tracks: snap.songs(a.songIDs).map(QueueItem.library))
    }
}
