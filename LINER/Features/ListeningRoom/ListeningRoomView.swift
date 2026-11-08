import SwiftUI

/// The Listening Room (double-tap the Vinyl Mode switch): a black turntable and a shelf of your most played
/// records, spines out. Tap a spine and the record comes off the shelf, cover first; tap the cover and it opens
/// like the gatefold, the record slipping out of the bottom of the tracklist; drag the record onto the
/// turntable and it drops on and plays, and the sleeve goes back on the shelf, sticking out a little.
struct ListeningRoomView: View {
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var held: Album?
    @State private var heldIndex = 0
    @State private var phase = Phase.shelf
    @State private var recordOut = false
    @State private var drag = CGSize.zero
    @State private var near = false
    @State private var flying = false
    @State private var recordGone = false
    @State private var dropKey: UUID?
    @State private var busy = false
    @State private var tint = Color.white
    /// The held record's cover, loaded once (the sleeve changes size as it moves, so it isn't reloaded per frame).
    @State private var cover: UIImage?

    enum Phase { case shelf, out, open }

    private var albums: [Album] {
        let played = library.stats.albums
        return Array((played.isEmpty ? library.recentlyAdded : played).prefix(14))
    }
    private var playingAlbumID: UInt64? { player.current?.song.flatMap { library.snapshot.albumOf($0)?.id } }

    var body: some View {
        GeometryReader { geo in
            let L = RoomLayout(size: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { if held != nil { Task { await stow(playing: false) } } }
                header(L)
                shelf(L)
                deck(L)
                status(L)
                if let album = held { sleeve(album, L) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { background.ignoresSafeArea() }
        .statusBarHidden()
        .keepsScreenAwake()
        .sensoryFeedback(.impact(weight: .light), trigger: phase)
        .sensoryFeedback(.selection, trigger: near)
    }

    // MARK: The room

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [tint.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
                .animation(.easeInOut(duration: 0.8), value: tint)
        }
    }

    private func header(_ L: RoomLayout) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(hint).font(.system(size: 10, weight: .semibold)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(held == nil ? Palette.label : tint)
                    .contentTransition(.opacity).animation(.easeInOut(duration: 0.2), value: hint)
                Text("Listening Room").font(.serif(28))
            }
            Spacer()
            GlassCircleButton(systemImage: "xmark", label: "Leave the Listening Room", size: 42) { dismiss() }
        }
        .frame(width: L.headerWidth)
        .offset(x: L.headerX, y: L.land ? L.shelf.minY - 78 : 6)
    }

    private var hint: String {
        switch (held, phase) {
        case (nil, _): "Vinyl Mode"
        case (_, .open): "Drag the record onto the turntable"
        default: "Tap the cover to open it"
        }
    }

    private func shelf(_ L: RoomLayout) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.06)))
                .shadow(color: .white.opacity(0.05), radius: 0, y: 8)
                .frame(width: L.shelf.width, height: L.shelf.height)
                .offset(x: L.shelf.minX, y: L.shelf.minY)
            ForEach(Array(albums.enumerated()), id: \.element.id) { i, a in
                let r = L.spine(i, of: albums.count), playing = a.id == playingAlbumID
                Button { Task { await pull(i) } } label: { RoomSpine(album: a, rect: r) }
                    .buttonStyle(.plain)
                    .opacity(held?.id == a.id ? 0 : 1)
                    .offset(x: r.minX, y: r.minY - (playing ? r.height * 0.07 : 0))
                    .shadow(color: playing ? tint.opacity(0.4) : .clear, radius: 8)
                    .accessibilityLabel("\(a.title) by \(a.artist)\(playing ? ", playing" : "")")
                    .accessibilityHint("Takes the record off the shelf")
            }
            .brightness(held == nil ? 0 : -0.45)
            .animation(.easeInOut(duration: 0.4), value: held?.id)
            .animation(.liner, value: playingAlbumID)
        }
    }

    @ViewBuilder private func deck(_ L: RoomLayout) -> some View {
        Group {
            if let item = player.current {
                PlayerVinyl(item: item, dropIn: dropKey != nil, dropDelay: 0.08).id(dropKey)
            } else {
                IdleDeck()
            }
        }
        .frame(width: L.deck.width, height: L.deck.height)
        .overlay {
            Circle().stroke(tint, lineWidth: 3).frame(width: L.deckRecord * 1.06, height: L.deckRecord * 1.06)
                .position(x: L.deckCenter.x - L.deck.minX, y: L.deckCenter.y - L.deck.minY)
                .opacity(near ? 0.8 : 0).animation(.easeOut(duration: 0.2), value: near)
                .allowsHitTesting(false)
        }
        .offset(x: L.deck.minX, y: L.deck.minY)
    }

    private func status(_ L: RoomLayout) -> some View {
        VStack(alignment: L.land ? .leading : .center, spacing: 6) {
            if let item = player.current {
                Text("Now playing").font(.system(size: 10, weight: .semibold)).tracking(2.5).textCase(.uppercase).foregroundStyle(tint)
                Text([item.title, item.song.flatMap { library.snapshot.albumOf($0)?.title }].compactMap { $0 }.joined(separator: " · "))
                    .font(.serif(19)).lineLimit(1)
            } else {
                Text("Tap a record on the shelf").font(.system(size: 14)).foregroundStyle(Palette.label)
            }
        }
        .multilineTextAlignment(L.land ? .leading : .center)
        .frame(width: L.status.width, height: L.status.height, alignment: L.land ? .topLeading : .center)
        .offset(x: L.status.minX, y: L.status.minY)
        .opacity(held == nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: held?.id)
    }

    // MARK: The record you're holding

    @ViewBuilder private func sleeve(_ album: Album, _ L: RoomLayout) -> some View {
        let record = VinylRecord.album(album, library.snapshot)
        let rect = phase == .shelf ? L.spine(heldIndex, of: albums.count) : phase == .out ? L.closed : L.open
        let discAt = flying ? L.deckCenter : (recordOut ? L.discOut : L.discIn)
        // The record, behind the tracklist until it slips out of the bottom.
        RecordDisc(record: record, side: "A")
            .frame(width: L.disc, height: L.disc)
            .rotationEffect(.degrees(recordOut && !flying ? 6 : 0))
            .scaleEffect(flying ? L.deckRecord * 1.2 / L.disc : (drag == .zero ? 1 : 1.04))
            .shadow(color: .black.opacity(0.7), radius: drag == .zero && !flying ? 8 : 24, y: drag == .zero && !flying ? 6 : 20)
            .contentShape(Circle())
            .gesture(recordDrag(L))
            .allowsHitTesting(phase == .open && !recordGone && !flying)
            .accessibilityLabel("The record").accessibilityHint("Drag it onto the turntable, or double-tap to put it on")
            .accessibilityAction { putOn(album) }
            .position(x: discAt.x + (flying ? 0 : drag.width), y: discAt.y + (flying ? 0 : drag.height))
            .opacity(phase == .open && (recordOut || flying) && !recordGone ? 1 : 0)
            .zIndex(drag == .zero && !flying ? 0 : 3)
        // The tracklist side, folded behind the cover until it opens.
        RoomTracklist(record: record, tint: tint)
            .scaleEffect(L.open.width / 300, anchor: .topLeading)
            .frame(width: L.open.width, height: L.open.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.7), radius: 18, y: 12)
            .rotation3DEffect(.degrees(phase == .open ? 0 : 90), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
            .opacity(phase == .open ? 1 : 0)
            .position(x: rect.maxX + rect.width / 2, y: rect.midY)
            .zIndex(1)
            .allowsHitTesting(false)
        // The cover.
        Group { if let cover { FillImage(image: cover) } else { Color(white: 0.12) } }
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(0.75), radius: 18, y: 12)
            .rotation3DEffect(.degrees(phase == .shelf ? -70 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .onTapGesture { if phase == .out { Task { await openSleeve() } } }
            .accessibilityLabel(album.title).accessibilityHint(phase == .out ? "Opens the sleeve" : "")
            .position(x: rect.midX, y: rect.midY)
            .zIndex(1)
            .task(id: album.id) {
                cover = CoverOverrides.shared.image(album.id)
                if cover == nil { cover = await ArtworkCache.shared.image(album: album.id, pixels: 900) }
                guard let img = cover else { return }
                tint = await ArtworkAnalysis.look(for: img, key: "room-\(album.id)").dominant.mix(with: .white, by: 0.35)
            }
    }

    private func recordDrag(_ L: RoomLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                guard phase == .open, !busy else { return }
                drag = v.translation
                near = hypot(L.discOut.x + v.translation.width - L.deckCenter.x, L.discOut.y + v.translation.height - L.deckCenter.y) < L.deckRecord * 0.4
            }
            .onEnded { v in
                guard phase == .open, !busy, let album = held else { return }
                let tapped = hypot(v.translation.width, v.translation.height) < 6
                if near || tapped { putOn(album) } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = .zero } }
                near = false
            }
    }

    // MARK: Actions

    /// Takes a record off the shelf; whatever you were holding goes back first.
    private func pull(_ i: Int) async {
        guard !busy, albums.indices.contains(i) else { return }
        if let h = held { if h.id == albums[i].id { return }; await stow(playing: false) }
        busy = true
        heldIndex = i; cover = CoverOverrides.shared.image(albums[i].id) ?? ArtworkCache.shared.cached(album: albums[i].id, pixels: 900); phase = .shelf; recordOut = false; drag = .zero; flying = false; recordGone = false
        held = albums[i]
        try? await Task.sleep(for: .milliseconds(30))
        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.7)) { phase = .out }
        try? await Task.sleep(for: .milliseconds(700))
        busy = false
    }

    /// Opens it like the gatefold, then the record slips out of the bottom of the tracklist.
    private func openSleeve() async {
        guard !busy, phase == .out else { return }
        busy = true
        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.8)) { phase = .open }
        try? await Task.sleep(for: .milliseconds(820))
        withAnimation(.timingCurve(0.3, 0, 0.3, 1, duration: 0.55)) { recordOut = true }
        try? await Task.sleep(for: .milliseconds(560))
        busy = false
    }

    /// Carries the record over the turntable; the deck takes over from there and drops it onto the plain record.
    private func putOn(_ album: Album) {
        guard !busy else { return }
        busy = true
        withAnimation(.easeInOut(duration: 0.4)) { flying = true; drag = .zero }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            player.play(library.snapshot.songs(album.songIDs).map(QueueItem.library))
            dropKey = UUID()
            recordGone = true
            try? await Task.sleep(for: .milliseconds(250))
            busy = false
            await stow(playing: true)
        }
    }

    /// Folds the sleeve shut and slides it back into its slot.
    private func stow(playing: Bool) async {
        guard !busy, held != nil else { return }
        busy = true
        if phase == .open {
            if !playing { withAnimation(.easeInOut(duration: 0.3)) { recordOut = false; drag = .zero } ; try? await Task.sleep(for: .milliseconds(280)) }
            recordGone = true
            withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.5)) { phase = .out }
            try? await Task.sleep(for: .milliseconds(480))
        }
        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.55)) { phase = .shelf }
        try? await Task.sleep(for: .milliseconds(560))
        held = nil; cover = nil; flying = false; recordGone = false; recordOut = false; drag = .zero
        busy = false
    }
}

#Preview {
    ListeningRoomView()
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
