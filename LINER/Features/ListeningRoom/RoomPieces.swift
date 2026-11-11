import SwiftUI

/// Where everything sits in the Listening Room. Portrait: the shelf at the top, the turntable at the bottom.
/// Landscape: the turntable on the left, the shelf on the right.
struct RoomLayout {
    let size: CGSize
    var land: Bool { size.width > size.height }

    var deck: CGRect {
        let w = size.width, h = size.height
        if land { let s = h * 0.9; return CGRect(x: w * 0.02, y: (h - s) / 2, width: s, height: s) }
        let s = min(w * 0.94, h * 0.42)
        return CGRect(x: (w - s) / 2, y: h - s - h * 0.01, width: s, height: s)
    }
    var shelf: CGRect {
        let w = size.width, h = size.height
        if land { let x = deck.maxX + w * 0.05; return CGRect(x: x, y: h * 0.25, width: w - x - w * 0.03, height: h * 0.5) }
        return CGRect(x: w * 0.05, y: 78, width: w * 0.9, height: h * 0.3)
    }
    /// The title row sits above the shelf.
    var headerX: CGFloat { land ? shelf.minX : size.width * 0.05 }
    var headerWidth: CGFloat { land ? shelf.width : size.width * 0.9 }
    var status: CGRect {
        land ? CGRect(x: shelf.minX, y: shelf.maxY + 14, width: shelf.width, height: size.height - shelf.maxY - 14)
             : CGRect(x: 0, y: shelf.maxY + 14, width: size.width, height: max(0, deck.minY - shelf.maxY - 14))
    }

    /// The coordinate space the room is laid out in (spines report where they are in it).
    static let space = "listeningRoom"

    /// One spine: about fourteen fit across the shelf; swipe along it for the rest.
    var spineSize: CGSize { CGSize(width: min(46, max(30, (shelf.width - 16) / 14 - 2)), height: shelf.height - 8) }
    /// How far the record that's playing sticks up out of the shelf.
    var raise: CGFloat { spineSize.height * 0.07 }
    /// Where a spine sits when its own place isn't known yet (the first slot).
    var firstSpine: CGRect { CGRect(origin: CGPoint(x: shelf.minX + 8, y: shelf.minY + 8), size: spineSize) }

    /// The sleeve pulled out, cover facing you.
    var closed: CGRect {
        let w = size.width, h = size.height
        if land { let c = h * 0.5; return CGRect(x: shelf.midX - c / 2, y: (h - c) / 2 - h * 0.04, width: c, height: c) }
        let c = w * 0.56
        return CGRect(x: (w - c) / 2, y: shelf.minY + h * 0.02, width: c, height: c)
    }
    /// The sleeve opened: this is the cover side; the tracklist is the same size to its right.
    var open: CGRect {
        let w = size.width, h = size.height
        if land { let o = min(h * 0.44, shelf.width * 0.48); return CGRect(x: shelf.midX - o, y: shelf.minY + h * 0.01, width: o, height: o) }
        let o = w * 0.46
        return CGRect(x: w / 2 - o, y: shelf.minY + h * 0.08, width: o, height: o)
    }

    var disc: CGFloat { open.width * 0.88 }
    /// The record inside the sleeve, behind the tracklist, and slipping out of its bottom edge.
    var discIn: CGPoint { CGPoint(x: open.maxX + open.width * 0.06 + disc / 2, y: open.minY + open.width * 0.06 + disc / 2) }
    var discOut: CGPoint { CGPoint(x: discIn.x, y: open.minY + open.width * 0.52 + disc / 2) }

    /// The record on the turntable (matches `DeckGeometry`).
    var deckCenter: CGPoint { CGPoint(x: deck.minX + deck.width * 0.45, y: deck.midY) }
    var deckRecord: CGFloat { deck.width * 0.84 }
}

/// The inside of a sleeve in the room: its tracklist, laid out at a fixed size and scaled to the panel.
struct RoomTracklist: View {
    let record: VinylRecord
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.05)
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(record.title).font(.serif(30)).lineLimit(1).minimumScaleFactor(0.6)
                Text(record.artist).font(.system(size: 11, weight: .semibold)).tracking(2).textCase(.uppercase).foregroundStyle(tint).padding(.top, 6)
                ForEach(Array(record.tracks.prefix(8).enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(record.sideLabel(i)).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.faint)
                            .frame(width: 30, alignment: .leading)
                        Text(t.title).font(.serif(17)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(t.duration.trackTime).font(.system(size: 11)).foregroundStyle(Palette.label).monospacedDigit()
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.09)).frame(height: 1) }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 24).padding(.top, 22)
        }
        .frame(width: 300, height: 300)
        .clipped()
    }
}

/// The playing record's setlist, sprung out of its label over the turntable (tap outside it to put it away).
struct RoomSetlist: View {
    let layout: RoomLayout
    let record: VinylRecord?
    let tint: Color
    @Binding var picking: Bool
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        let L = layout
        ZStack {
            if picking, let record {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { picking = false }.transition(.opacity)
                SetlistCard(record: record, currentID: player.current?.id, tint: tint, pick: { i in
                    picking = false
                    SetlistPlay.play(record, at: i, player: player)
                }, close: { picking = false })
                .frame(width: min(L.size.width - 32, L.deckRecord * 1.08), height: min(L.size.height * 0.8, L.deckRecord * 1.08))
                .position(L.deckCenter)
                .transition(.outOfTheLabel)
            }
        }
        .frame(width: L.size.width, height: L.size.height)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: picking)
    }
}

/// The turntable with nothing playing: a plain black record and the arm at rest.
struct IdleDeck: View {
    var body: some View {
        GeometryReader { geo in
            let d = DeckGeometry(size: min(geo.size.width, geo.size.height))
            ZStack {
                RoundedRectangle(cornerRadius: d.size * 0.06, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.1), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: d.size * 0.06, style: .continuous).stroke(.white.opacity(0.07)))
                    .shadow(color: .black.opacity(0.7), radius: 30, y: 18)
                Canvas { ctx, _ in TonearmDrawing.platter(&ctx, deck: d, spin: 0) }
                RecordDisc(record: VinylRecord(id: "plain", title: "", artist: "", year: nil, albumID: nil, coverData: nil, tracks: []),
                           side: "A", plain: true)
                    .frame(width: d.radius * 2, height: d.radius * 2)
                    .position(d.center)
                Canvas { ctx, _ in TonearmDrawing.draw(&ctx, deck: d, angle: d.rest, lifted: true) }
            }
            .frame(width: d.size, height: d.size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    let a = PreviewData.snapshot.albums[0]
    HStack(spacing: 20) {
        RoomSpine(record: .album(a, PreviewData.snapshot), size: CGSize(width: 30, height: 220))
        RoomTracklist(record: .album(a, PreviewData.snapshot), tint: .orange).scaleEffect(0.6).frame(width: 180, height: 180)
        IdleDeck().frame(width: 200)
    }
    .padding().background(.black).environment(PreviewData.library).preferredColorScheme(.dark)
}
