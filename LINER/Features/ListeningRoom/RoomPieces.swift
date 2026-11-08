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

    func spine(_ i: Int, of n: Int) -> CGRect {
        let inner = shelf.insetBy(dx: 8, dy: 0), gap: CGFloat = 2
        let w = min(46, (inner.width - gap * CGFloat(max(n - 1, 0))) / CGFloat(max(n, 1)))
        return CGRect(x: inner.minX + CGFloat(i) * (w + gap), y: shelf.minY + 8, width: w, height: shelf.height - 8)
    }

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

/// A record on the shelf, spine out: the title and artist in the colours of its cover.
struct RoomSpine: View {
    let album: Album
    let rect: CGRect
    @State private var colour = Color(white: 0.16)
    @State private var light = false

    var body: some View {
        ZStack {
            colour
            LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.78), .init(color: .black.opacity(0.5), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 8) {
                Text(album.title).font(.serif(min(15, rect.width * 0.46)))
                Text(album.artist).font(.system(size: min(8, rect.width * 0.24), weight: .semibold)).tracking(1.4).textCase(.uppercase).opacity(0.7)
            }
            .lineLimit(1)
            .foregroundStyle(light ? Color.black.opacity(0.85) : Color.white.opacity(0.92))
            .frame(width: rect.height - 16, alignment: .leading)
            .rotationEffect(.degrees(90))
            .frame(width: rect.width, height: rect.height)
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
        .task(id: album.id) {
            guard let img = await ArtworkCache.shared.image(album: album.id, pixels: 96),
                  let rgb = Self.average(img) else { return }
            let (r, g, b) = rgb
            withAnimation(.easeOut(duration: 0.3)) {
                colour = Color(red: r, green: g, blue: b)
                light = 0.299 * r + 0.587 * g + 0.114 * b > 0.62
            }
        }
    }

    /// The cover's average colour: the small image squeezed into one pixel (quick, unlike the full analysis).
    static func average(_ image: UIImage) -> (Double, Double, Double)? {
        guard let cg = image.cgImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        return (Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255)
    }
}

/// The inside of a sleeve in the room: its tracklist, laid out at a fixed size and scaled to the panel.
struct RoomTracklist: View {
    let record: VinylRecord
    let tint: Color

    var body: some View {
        let n = record.tracks.count, half = (n + 1) / 2
        ZStack(alignment: .topLeading) {
            Color(white: 0.05)
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(record.title).font(.serif(30)).lineLimit(1).minimumScaleFactor(0.6)
                Text(record.artist).font(.system(size: 11, weight: .semibold)).tracking(2).textCase(.uppercase).foregroundStyle(tint).padding(.top, 6)
                ForEach(Array(record.tracks.prefix(8).enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(i < half ? "A\(i + 1)" : "B\(i - half + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.faint)
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
        RoomSpine(album: a, rect: CGRect(x: 0, y: 0, width: 30, height: 220))
        RoomTracklist(record: .album(a, PreviewData.snapshot), tint: .orange).scaleEffect(0.6).frame(width: 180, height: 180)
        IdleDeck().frame(width: 200)
    }
    .padding().background(.black).environment(PreviewData.library).preferredColorScheme(.dark)
}
