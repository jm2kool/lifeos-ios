import SwiftData
import SwiftUI

/// The Listening Room (double-tap the Vinyl Mode switch): a black turntable and a shelf of records, spines out —
/// your most played albums until you fill it yourself. Swipe along the shelf for more; the end slot adds albums
/// and mixtapes, and holding a spine takes it off or arranges its sides. Tap a spine and the record comes off the
/// shelf, cover first; tap the cover and it opens like the gatefold, the record slipping out of the bottom of the
/// tracklist; drag the record onto the turntable and it drops on and plays, and the sleeve goes back on the
/// shelf, sticking out a little. Tap the label in the middle of the playing record to pick a song.
struct ListeningRoomView: View {
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]
    @State private var held: VinylRecord?
    @State private var phase = Phase.shelf
    @State private var recordOut = false
    @State private var drag = CGSize.zero
    @State private var near = false
    @State private var flying = false
    @State private var recordGone = false
    @State private var dropKey: UUID?
    /// The sleeve is going back to the shelf; a record tapped meanwhile comes out once it's in.
    @State private var stowing = false
    @State private var pending: VinylRecord?
    @State private var tint = Color.white
    /// The held record's cover, loaded once (the sleeve changes size as it moves, so it isn't reloaded per frame).
    @State private var cover: UIImage?
    /// Where each spine is on screen, so a record comes off the shelf from its own place.
    @State private var frames = SleeveFrames()
    /// The record you put on, for the setlist.
    @State private var onDeck: VinylRecord?
    @State private var picking = false
    @State private var editingShelf = false
    @State private var arranging: VinylRecord?

    enum Phase { case shelf, out, open }

    private var records: [VinylRecord] { RoomShelf.shared.records(library, mixtapes: mixtapes) }
    private var playingID: String? { player.current?.artworkKey }

    /// What's on the turntable: the record you put on, or the album of the song playing.
    private var deckRecord: VinylRecord? {
        guard let id = player.current?.id else { return nil }
        if let onDeck, onDeck.tracks.contains(where: { $0.id == id }) { return onDeck.sided() }
        if let song = player.current?.song, let album = library.snapshot.albumOf(song) { return .album(album, library.snapshot) }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let L = RoomLayout(size: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { if held != nil, !flying { stow() } }
                header(L)
                shelf(L)
                deck(L)
                status(L)
                if let record = held { sleeve(record, L) }
                RoomSetlist(layout: L, record: deckRecord, tint: tint, picking: $picking)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(.named(RoomLayout.space))
        }
        .background { background.ignoresSafeArea() }
        .statusBarHidden()
        .keepsScreenAwake()
        .sensoryFeedback(.impact(weight: .light), trigger: phase)
        .sensoryFeedback(.selection, trigger: near)
        .sheet(isPresented: $editingShelf) { ShelfPicker(current: records) }
        .sheet(item: $arranging) { SidesEditor(record: $0) }
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
            GlassCircleButton(systemImage: "books.vertical", label: "Fill the shelf", size: 42) { editingShelf = true }
                .padding(.trailing, 4)
            GlassCircleButton(systemImage: "xmark", label: "Leave the Listening Room", size: 42) { dismiss() }
        }
        .frame(width: L.headerWidth, height: 60)
        .position(x: L.headerX + L.headerWidth / 2, y: (L.land ? L.shelf.minY - 78 : 6) + 30)
    }

    private var hint: String {
        switch (held, phase) {
        case (nil, _): "Vinyl Mode"
        case (_, .open): "Drag the record onto the turntable"
        default: "Tap the cover to open it"
        }
    }

    private func shelf(_ L: RoomLayout) -> some View {
        let list = records
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.06)))
                .shadow(color: .white.opacity(0.05), radius: 0, y: 8)
                .frame(height: L.shelf.height)
            RoomShelfStrip(records: list, spine: L.spineSize, raise: L.raise + 4, heldID: held?.id, playingID: playingID, tint: tint,
                           frames: frames, pull: pull, edit: { editingShelf = true },
                           remove: { r in RoomShelf.shared.remove(r.id, from: list.map(\.id)) },
                           arrange: { arranging = $0 })
                .frame(height: L.spineSize.height + L.raise + 8)
        }
        .frame(width: L.shelf.width, height: L.shelf.height + L.raise + 8, alignment: .bottom)
        .position(x: L.shelf.midX, y: L.shelf.maxY - (L.shelf.height + L.raise + 8) / 2)
    }

    @ViewBuilder private func deck(_ L: RoomLayout) -> some View {
        Group {
            if let item = player.current {
                PlayerVinyl(item: item, side: deckRecord?.side(of: item.id) ?? "A", dropIn: dropKey != nil, dropDelay: 0.08,
                            onLabelTap: { if deckRecord != nil { picking = true } else { player.togglePlayPause() } })
                    .id(dropKey)
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
        .position(x: L.deck.midX, y: L.deck.midY)
    }

    private func status(_ L: RoomLayout) -> some View {
        VStack(alignment: L.land ? .leading : .center, spacing: 6) {
            if let item = player.current {
                Text("Now playing").font(.system(size: 10, weight: .semibold)).tracking(2.5).textCase(.uppercase).foregroundStyle(tint)
                Text([item.title, deckRecord?.title ?? item.song.flatMap { library.snapshot.albumOf($0)?.title }].compactMap { $0 }.joined(separator: " · "))
                    .font(.serif(19)).lineLimit(1)
                if deckRecord != nil {
                    Text("Tap the label to pick a song").font(.system(size: 12)).foregroundStyle(Palette.label)
                }
            } else {
                Text("Tap a record on the shelf").font(.system(size: 14)).foregroundStyle(Palette.label)
            }
        }
        .multilineTextAlignment(L.land ? .leading : .center)
        .frame(width: L.status.width, height: L.status.height, alignment: L.land ? .topLeading : .center)
        .position(x: L.status.midX, y: L.status.midY)
        .opacity(held == nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: held?.id)
    }

    // MARK: The record you're holding

    @ViewBuilder private func sleeve(_ record: VinylRecord, _ L: RoomLayout) -> some View {
        let rect = phase == .shelf ? (frames.rects[record.id] ?? L.firstSpine) : phase == .out ? L.closed : L.open
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
            .accessibilityAction { putOn(record) }
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
            .contentShape(Rectangle())
            .onTapGesture { openSleeve() }
            // Comes off the shelf as soon as it's there (no timers to miss).
            .onAppear { withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.7)) { phase = .out } }
            .accessibilityLabel(record.title).accessibilityHint(phase == .out ? "Opens the sleeve" : "")
            .position(x: rect.midX, y: rect.midY)
            .zIndex(1)
            .task(id: record.id) {
                if let data = record.coverData { cover = UIImage(data: data) }
                else if let id = record.albumID {
                    cover = CoverOverrides.shared.image(id)
                    if cover == nil { cover = await ArtworkCache.shared.image(album: id, pixels: 640) }
                }
                guard let img = cover else { return }
                tint = await ArtworkAnalysis.look(for: img, key: "room-\(record.id)").dominant.mix(with: .white, by: 0.35)
            }
    }

    private func recordDrag(_ L: RoomLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                guard phase == .open, recordOut, !flying, !stowing else { return }
                drag = v.translation
                near = hypot(L.discOut.x + v.translation.width - L.deckCenter.x, L.discOut.y + v.translation.height - L.deckCenter.y) < L.deckRecord * 0.4
            }
            .onEnded { v in
                guard phase == .open, recordOut, !flying, !stowing, let record = held else { return }
                let tapped = hypot(v.translation.width, v.translation.height) < 6
                if near || tapped { putOn(record) } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = .zero } }
                near = false
            }
    }

    // MARK: Actions

    /// Takes a record off the shelf (it comes out from its slot as it appears); whatever you were holding goes
    /// back first.
    private func pull(_ record: VinylRecord) {
        guard !flying else { return }
        picking = false
        if let h = held {
            guard h.id != record.id else { return }
            pending = record
            stow()
            return
        }
        phase = .shelf; recordOut = false; drag = .zero; recordGone = false
        if let data = record.coverData { cover = UIImage(data: data) }
        else { cover = record.albumID.flatMap { CoverOverrides.shared.image($0) ?? ArtworkCache.shared.cached(album: $0, pixels: 640) } }
        held = record
    }

    /// Opens it like the gatefold, then the record slips out of the bottom of the tracklist.
    private func openSleeve() {
        guard held != nil, phase == .out, !stowing else { return }
        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.8)) { phase = .open } completion: {
            guard phase == .open, !stowing else { return }
            withAnimation(.timingCurve(0.3, 0, 0.3, 1, duration: 0.55)) { recordOut = true }
        }
    }

    /// Carries the record over the turntable; the deck takes over from there and drops it onto the plain record.
    private func putOn(_ record: VinylRecord) {
        guard !flying else { return }
        withAnimation(.easeInOut(duration: 0.4)) { flying = true; drag = .zero } completion: {
            player.play(record.tracks, openPlayer: false)
            onDeck = record
            dropKey = UUID()
            recordGone = true
            stow(playing: true)
        }
    }

    /// Folds the sleeve shut and slides it back into its slot.
    private func stow(playing: Bool = false) {
        guard held != nil, !stowing else { return }
        stowing = true
        if phase == .open {
            withAnimation(.easeInOut(duration: 0.3)) { if !playing { recordOut = false }; drag = .zero } completion: {
                recordGone = true
                withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.5)) { phase = .out } completion: { toShelf() }
            }
        } else {
            toShelf()
        }
    }

    private func toShelf() {
        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.55)) { phase = .shelf } completion: {
            held = nil; cover = nil; flying = false; recordGone = false; recordOut = false; drag = .zero; stowing = false
            if let next = pending { pending = nil; pull(next) }
        }
    }
}

#Preview {
    ListeningRoomView()
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
