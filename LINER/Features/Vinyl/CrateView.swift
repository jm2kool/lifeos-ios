import SwiftData
import SwiftUI

/// Home in Vinyl Mode: flip through sleeves in 3D (a tick under your finger for each record), the backdrop takes
/// the colours of the record in front. Tap a sleeve to open it; "Put it on" carries it to the turntable.
struct CrateView: View {
    /// Opens Settings from the crate's header.
    var onSettings: () -> Void = {}
    @Environment(LibraryService.self) private var library
    @Query(filter: #Predicate<AlbumNote> { $0.pinned }, sort: \AlbumNote.pinnedAt) private var pins: [AlbumNote]
    @Query(sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]
    @Query(sort: \MoodPlaylist.createdAt, order: .reverse) private var moods: [MoodPlaylist]
    @AppStorage("crate.filter") private var filter: CrateFilter = .recent
    @AppStorage("vinylMode") private var vinylMode = false
    @State private var focused: String?
    @State private var playing: VinylRecord?
    @State private var backdrop: UIImage?
    @State private var taps = 0

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
        .task(id: current?.id) { await loadBackdrop(current) }
        .task { VinylSounds.shared.prepare() }
        .fullScreenCover(item: $playing) { r in
            TurntableView(record: r)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .toolbar(.hidden, for: .navigationBar)
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
            Toggle("Vinyl Mode", isOn: $vinylMode.animation(.liner)).labelsHidden()
                .accessibilityLabel("Vinyl Mode")
                .accessibilityHint("Turn off to go back to the normal Home")
            GlassCircleButton(systemImage: "gearshape", label: "Settings", size: 44, action: onSettings)
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
                    open(r) {
                        VStack(spacing: 6) {
                            SleeveView(record: r, peek: isFront ? 0.32 : 0.12).frame(width: side, height: side)
                            // A soft reflection on the floor.
                            RecordCover(record: r, cornerRadius: 4).frame(width: side, height: side * 0.35, alignment: .top).clipped()
                                .scaleEffect(x: 1, y: -1).opacity(0.18).blur(radius: 2)
                                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .rotation3DEffect(.degrees(phase.value * -42), axis: (x: 0, y: 1, z: 0))
                            .scaleEffect(phase.isIdentity ? 1 : 0.84)
                            .opacity(phase.isIdentity ? 1 : 0.7)
                    }
                    .zIndex(isFront ? 1 : 0)
                    .id(r.id)
                    .accessibilityLabel("\(r.title) by \(r.artist)")
                    .accessibilityHint("Double-tap to open it")
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

    /// A sleeve opens its album, mixtape or mood playlist page; nothing plays until you put it on.
    @ViewBuilder private func open<L: View>(_ r: VinylRecord, @ViewBuilder label: () -> L) -> some View {
        switch r.source {
        case .album(let a): NavigationLink(value: a, label: label).buttonStyle(.plain).simultaneousGesture(TapGesture().onEnded { taps += 1 })
        case .mixtape(let m): NavigationLink(value: m, label: label).buttonStyle(.plain).simultaneousGesture(TapGesture().onEnded { taps += 1 })
        case .mood(let p): NavigationLink(value: p, label: label).buttonStyle(.plain).simultaneousGesture(TapGesture().onEnded { taps += 1 })
        case nil: Button(action: { putOn(r) }, label: label).buttonStyle(.plain)
        }
    }

    /// The record in front's name, and the one "Put it on" button. Only the words change as you flip — the
    /// button itself stays put, so it never flickers or jumps under your thumb.
    private func details(_ r: VinylRecord) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 6) {
                Text(r.title).font(.serif(26)).lineLimit(1).padding(.horizontal, 24)
                Text([r.artist, r.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")).linerLabel(size: 10)
            }
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: r.id)
            Button { putOn(r) } label: {
                Label("Put it on", systemImage: "record.circle").font(.system(size: 17, weight: .bold)).frame(width: 190, height: 52)
            }
            .buttonStyle(.linerPrimary).buttonBorderShape(.capsule)
            .padding(.top, 14)
        }
    }

    /// Starts the music first, then slides the turntable up on the next frame, so the queue loading never
    /// stutters the animation (and the song still starts at once).
    private func putOn(_ r: VinylRecord) {
        taps += 1
        PlaybackCoordinator.shared?.play(r.tracks, openPlayer: false)
        VinylSounds.shared.needleDrop()
        Task { await Task.yield(); playing = r }
    }

    private func loadBackdrop(_ r: VinylRecord?) async {
        guard let r else { return }
        if let data = r.coverData { backdrop = UIImage(data: data); return }
        guard let id = r.albumID else { return }
        if let mine = CoverOverrides.shared.image(id) { backdrop = mine; return }
        backdrop = await ArtworkCache.shared.image(album: id, pixels: 320)
    }

    private var records: [VinylRecord] {
        let snap = library.snapshot
        switch filter {
        case .pinned:
            return pins.compactMap { n in UInt64(n.albumID.dropFirst(6)).flatMap { snap.album($0) }.map { VinylRecord.album($0, snap) } }
        case .recent: return library.recentlyAdded.prefix(30).map { VinylRecord.album($0, snap) }
        case .all: return library.albums(.alphabetical).map { VinylRecord.album($0, snap) }
        case .mostPlayed: return library.stats.albums.prefix(30).map { VinylRecord.album($0, snap) }
        case .mixtapes:
            return mixtapes.map { m in
                VinylRecord(id: "mixtape-\(m.id)", title: m.title, artist: m.artist, year: m.year, albumID: nil, coverData: m.coverImage,
                            tracks: m.orderedTracks.map { .local(TrackResolver.local($0)) }, source: .mixtape(m))
            }
        case .moods:
            return moods.map { p in
                let songs = MoodPlaylistService.songs(p, library: library)
                return VinylRecord(id: "mood-\(p.id)", title: p.name, artist: "Mood playlist", year: nil, albumID: songs.first?.albumID,
                                   coverData: nil, tracks: songs.map(QueueItem.library), source: .mood(p))
            }
        }
    }
}

extension VinylRecord {
    static func album(_ a: Album, _ snap: LibrarySnapshot) -> VinylRecord {
        VinylRecord(id: "album-\(a.id)", title: a.title, artist: a.artist, year: a.year, albumID: a.id, coverData: nil,
                    tracks: snap.songs(a.songIDs).map(QueueItem.library), source: .album(a))
    }
}
