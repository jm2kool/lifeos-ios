import SwiftUI

/// An album in Vinyl Mode, opened like a gatefold sleeve: it lifts out of the crate, opens from the spine on both
/// sides, and you step inside. Portrait: the cover fills the screen and the tracklist is a swipe to the right.
/// Landscape: both sides sit next to each other as squares. "Put it on" slides the record out onto the turntable.
struct GatefoldView: View {
    let record: VinylRecord
    /// Where the sleeve was in the crate (global coordinates), so it lifts from there; nil opens it in place.
    var source: CGRect?
    let onClose: () -> Void

    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = Stage.closed
    /// The real swipeable spread takes over once the sleeve has opened (portrait).
    @State private var settled = false
    @State private var page: Int? = 0
    @State private var cover: UIImage?
    @State private var tint = Color.white
    @State private var recordOut = false
    @State private var turntable: VinylRecord?
    @State private var busy = false
    /// The sides editor, open for this record.
    @State private var arranging: VinylRecord?
    /// Full Album (as Apple Music lists it, the songs you don't have streamed) or Saved Album, shared with the
    /// album page.
    @AppStorage(AlbumTracklist.storageKey) private var savedOnlyAlbums = ""
    @State private var catalog: [AppleCatalog.Track]?

    enum Stage { case closed, lifted, opening, flat, inside }

    private struct Placement {
        var left: CGRect, right: CGRect
        var leftAngle = 0.0, rightAngle = 0.0, rightOpacity = 1.0, corner: CGFloat = 6, dim = 0.92
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size, origin = geo.frame(in: .global).origin
            let land = size.width > size.height
            let now = placement(stage, size: size, origin: origin)
            let final = placement(.inside, size: size, origin: origin)
            let inset = land ? 0 : room
            ZStack(alignment: .topLeading) {
                Color.black.opacity(now.dim).ignoresSafeArea()
                if settled && !land {
                    spread(size: size, inset: inset)
                } else {
                    coverPanel(final.left.size, inside: stage == .inside, inset: inset)
                        .frame(width: now.left.width, height: now.left.height)
                        .clipShape(RoundedRectangle(cornerRadius: now.corner, style: .continuous))
                        .rotation3DEffect(.degrees(now.leftAngle), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.6)
                        .position(x: now.left.midX, y: now.left.midY)
                    scaled(tracksPanel(final.right.size, inset: inset), final: final.right.size, to: now.right.size)
                        .clipShape(RoundedRectangle(cornerRadius: now.corner, style: .continuous))
                        .rotation3DEffect(.degrees(now.rightAngle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
                        .opacity(now.rightOpacity)
                        .position(x: now.right.midX, y: now.right.midY)
                }
                chrome(land: land, inset: inset).opacity(stage == .inside ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(stage == .inside)
        .task { await load() }
        .task { await open() }
        .sheet(item: $arranging) { SidesEditor(record: $0) }
        .fullScreenCover(item: $turntable, onDismiss: { withAnimation(.liner) { recordOut = false } }) { TurntableView(record: $0, dropIn: true) }
    }

    // MARK: Where things are

    /// Room kept at the bottom for the mini player while something's playing, so it never covers the sleeve's
    /// title, the page dots or "Put it on".
    private var room: CGFloat { player.current == nil ? 0 : 84 }

    /// The two sides of the sleeve at each stage: lifted from the crate, opening from the spine (both sides
    /// angled like a half-open gatefold), lying flat, then grown to fill the screen.
    private func placement(_ stage: Stage, size: CGSize, origin: CGPoint) -> Placement {
        let w = size.width, h = size.height, m = min(w, h), land = w > h
        let s1 = m * 0.7, lifted = CGRect(x: (w - s1) / 2, y: (h - s1) / 2 - h * 0.03, width: s1, height: s1)
        let s2 = land ? m * 0.6 : w * 0.47
        let open = CGRect(x: w / 2 - s2, y: (h - s2) / 2 - h * 0.03, width: s2, height: s2)
        let beside = { (r: CGRect) in r.offsetBy(dx: r.width, dy: 0) }
        switch stage {
        case .closed:
            let start = source.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) } ?? lifted.insetBy(dx: s1 * 0.12, dy: s1 * 0.12)
            return Placement(left: start, right: beside(start), rightAngle: 90, rightOpacity: 0, corner: 4, dim: 0)
        case .lifted:
            return Placement(left: lifted, right: beside(lifted), rightAngle: 90, rightOpacity: 0)
        case .opening:
            return Placement(left: open.offsetBy(dx: -s2 * 0.02, dy: 0), right: beside(open), leftAngle: -26, rightAngle: 26)
        case .flat:
            return Placement(left: open, right: beside(open))
        case .inside:
            guard land else { return Placement(left: CGRect(origin: .zero, size: size), right: CGRect(x: w, y: 0, width: w, height: h), corner: 0, dim: 1) }
            // Two squares side by side with a plain gap between them.
            let tall = h - room * 0.8
            let gap = max(12, h * 0.045), side = min(tall * 0.92, (w - gap - w * 0.12) / 2)
            let left = CGRect(x: (w - side * 2 - gap) / 2, y: (tall - side) / 2, width: side, height: side)
            return Placement(left: left, right: left.offsetBy(dx: side + gap, dy: 0), corner: 8, dim: 1)
        }
    }

    /// Lays the tracklist out at its finished size and scales it, so it reads like a printed panel while it opens.
    private func scaled<V: View>(_ content: V, final: CGSize, to now: CGSize) -> some View {
        content
            .frame(width: final.width, height: final.height)
            .scaleEffect(final.width > 0 ? now.width / final.width : 1, anchor: .topLeading)
            .frame(width: now.width, height: now.height, alignment: .topLeading)
            .clipped()
    }

    // MARK: Pieces

    /// Portrait, once open: a paged spread, folding a little at the crease as you swipe.
    private func spread(size: CGSize, inset: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                coverPanel(size, inside: true, inset: inset).frame(width: size.width, height: size.height).id(0)
                    .scrollTransition(axis: .horizontal) { c, phase in
                        c.rotation3DEffect(.degrees(phase.value * -18), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.6)
                    }
                tracksPanel(size, inset: inset).frame(width: size.width, height: size.height).id(1)
                    .scrollTransition(axis: .horizontal) { c, phase in
                        c.rotation3DEffect(.degrees(phase.value * -18), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
                    }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .sensoryFeedback(.selection, trigger: page)
    }

    private func coverPanel(_ size: CGSize, inside: Bool, inset: CGFloat) -> some View {
        GatefoldCover(record: shown, album: album, cover: cover, tint: tint, width: size.width, showsHint: size.width < size.height,
                      bottomInset: inset)
            .environment(\.gatefoldMetaVisible, inside)
    }

    private func tracksPanel(_ size: CGSize, inset: CGFloat) -> some View {
        GatefoldTracks(record: shown, cover: cover, tint: tint, width: size.width, tall: size.height > size.width + 1, recordOut: recordOut,
                       nowPlayingID: player.current?.id, tracklist: tracklistChoice, bottomInset: inset,
                       onArrange: { arranging = shown }) { putOn(at: $0) }
    }

    private func chrome(land: Bool, inset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            GlassCircleButton(systemImage: "chevron.left", label: "Close the sleeve", size: 44) { Task { await close() } }
                .padding(.leading, land ? 24 : 20).padding(.top, land ? 20 : 62)
            if !land {
                HStack(spacing: 6) {
                    ForEach(0..<2) { i in
                        Capsule().fill(.white.opacity(page == i ? 1 : 0.3)).frame(width: page == i ? 22 : 14, height: 4)
                            .onTapGesture { withAnimation(.liner) { page = i } }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 26 + inset)
                .animation(.liner, value: page)
            }
        }
        .allowsHitTesting(stage == .inside)
    }

    // MARK: Actions

    private var album: Album? { if case .album(let a) = record.source { a } else { nil } }

    private var savedOnly: Bool { AlbumTracklist.savedOnly(record.id, in: savedOnlyAlbums) }

    /// Every song on the album: yours where you have them, the rest streamed from Apple Music.
    private var full: [QueueItem]? {
        guard let album, let catalog, catalog.count >= album.songIDs.count else { return nil }
        let mine = library.snapshot.songsByStoreID
        return catalog.map { .library($0.song(in: library.snapshot, byStoreID: mine)) }
    }

    /// The record as shown: the full album unless you chose Saved Album for it.
    private var shown: VinylRecord {
        guard album != nil, !savedOnly, let full else { return record.sided() }
        return VinylRecord(id: record.id, title: record.title, artist: record.artist, year: record.year, albumID: record.albumID,
                           coverData: record.coverData, tracks: full, source: record.source).sided()
    }

    /// The Full Album / Saved Album switch on the tracklist side (albums only).
    private var tracklistChoice: GatefoldTracks.Choice? {
        guard album != nil else { return nil }
        return GatefoldTracks.Choice(savedOnly: savedOnly || full == nil, fullAvailable: full != nil, fullCount: full?.count,
                                     savedCount: record.tracks.count) { saved in
            savedOnlyAlbums = AlbumTracklist.setting(record.id, savedOnly: saved, in: savedOnlyAlbums)
        }
    }

    private func load() async {
        if let data = record.coverData { cover = UIImage(data: data) }
        else if let id = record.albumID {
            cover = CoverOverrides.shared.image(id)
            if cover == nil { cover = await ArtworkCache.shared.image(album: id, pixels: 1400) }
        }
        if let album {
            let ids = library.snapshot.songs(album.songIDs).filter(\.hasStoreID).map(\.storeID)
            if !ids.isEmpty { catalog = await AppleCatalog.fullAlbum(songStoreIDs: ids) }
        }
        if let cover { tint = await ArtworkAnalysis.look(for: cover, key: "gatefold-\(record.id)").dominant.mix(with: .white, by: 0.35) }
    }

    private func open() async {
        guard stage == .closed else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) { stage = .inside }
            settled = true
            return
        }
        busy = true
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)) { stage = .lifted }
        try? await Task.sleep(for: .milliseconds(520))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.45)) { stage = .opening }
        try? await Task.sleep(for: .milliseconds(430))
        withAnimation(.easeOut(duration: 0.32)) { stage = .flat }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.7)) { stage = .inside }
        try? await Task.sleep(for: .milliseconds(720))
        settled = true
        busy = false
    }

    /// The same moves backwards, into the crate.
    private func close() async {
        guard !busy else { return }
        busy = true
        if page != 0 { withAnimation(.liner) { page = 0 }; try? await Task.sleep(for: .milliseconds(380)) }
        settled = false
        if reduceMotion { onClose(); return }
        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.6)) { stage = .flat }
        try? await Task.sleep(for: .milliseconds(580))
        withAnimation(.easeInOut(duration: 0.4)) { stage = .lifted }
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) { stage = .closed }
        try? await Task.sleep(for: .milliseconds(450))
        onClose()
    }

    /// The music starts at once; the record slides out of the inner sleeve and the turntable comes up, where it
    /// drops onto the plain record waiting there.
    private func putOn(at index: Int) {
        let r = shown
        guard !r.tracks.isEmpty else { return }
        player.play(r.tracks, startAt: index, openPlayer: false)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.35)) { recordOut = true }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            turntable = r
        }
    }
}

extension EnvironmentValues {
    /// Whether the cover side shows its title and credits (only once the sleeve is fully open).
    @Entry var gatefoldMetaVisible = true
}

#Preview {
    GatefoldView(record: .album(PreviewData.snapshot.albums[0], PreviewData.snapshot), onClose: {})
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
