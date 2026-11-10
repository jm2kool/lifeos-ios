import SwiftUI

/// The Listening Room's shelf: records spine out, side by side; swipe along it for more. The one playing sticks
/// up a little. Hold a spine to take it off the shelf or arrange its sides; the slot at the end adds records.
/// Each spine says where it is, so a record comes off the shelf from its own place.
struct RoomShelfStrip: View {
    let records: [VinylRecord]
    let spine: CGSize
    let raise: CGFloat
    let heldID: String?
    let playingID: String?
    let tint: Color
    let frames: SleeveFrames
    let pull: (VinylRecord) -> Void
    let edit: () -> Void
    let remove: (VinylRecord) -> Void
    let arrange: (VinylRecord) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(records) { r in
                    let playing = r.id == playingID
                    RoomSpine(record: r, size: spine)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RoomLayout.space)) } action: { frames.rects[r.id] = $0 }
                        .contentShape(Rectangle())
                        .onTapGesture { pull(r) }
                        .contextMenu {
                            Button("Arrange Sides", systemImage: "square.split.2x1") { arrange(r) }
                            Button("Take Off the Shelf", systemImage: "minus.circle", role: .destructive) { remove(r) }
                        }
                        .opacity(heldID == r.id ? 0 : 1)
                        .offset(y: playing ? -raise : 0)
                        .shadow(color: playing ? tint.opacity(0.4) : .clear, radius: 8)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("\(r.title) by \(r.artist)\(playing ? ", playing" : "")")
                        .accessibilityHint("Takes the record off the shelf")
                        .accessibilityAction { pull(r) }
                        .accessibilityAction(named: "Arrange sides") { arrange(r) }
                        .accessibilityAction(named: "Take off the shelf") { remove(r) }
                }
                addSlot
            }
            .padding(.horizontal, 8)
            .padding(.top, raise + 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .brightness(heldID == nil ? 0 : -0.45)
            .animation(.easeInOut(duration: 0.4), value: heldID)
            .animation(.liner, value: playingID)
            .animation(.liner, value: records.map(\.id))
        }
        .scrollDisabled(heldID != nil)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                   .init(color: .black, location: 0.97), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }

    /// The empty slot at the end of the shelf: put more records on it.
    private var addSlot: some View {
        Button(action: edit) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .overlay { Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.label) }
                .frame(width: spine.width, height: spine.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .accessibilityLabel("Add records to the shelf")
    }
}

/// A record on the shelf, spine out: the title and artist in the colours of its cover.
struct RoomSpine: View {
    let record: VinylRecord
    let size: CGSize
    @State private var colour = Color(white: 0.16)
    @State private var light = false

    var body: some View {
        ZStack {
            colour
            LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.78), .init(color: .black.opacity(0.5), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 8) {
                Text(record.title).font(.serif(min(15, size.width * 0.46)))
                Text(record.artist).font(.system(size: min(8, size.width * 0.24), weight: .semibold)).tracking(1.4).textCase(.uppercase).opacity(0.7)
            }
            .lineLimit(1)
            .foregroundStyle(light ? Color.black.opacity(0.85) : Color.white.opacity(0.92))
            .frame(width: size.height - 16, alignment: .leading)
            .rotationEffect(.degrees(90))
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
        .task(id: record.id) {
            var img: UIImage?
            if let data = record.coverData { img = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 96, height: 96)) }
            else if let id = record.albumID {
                img = CoverOverrides.shared.image(id)
                if img == nil { img = await ArtworkCache.shared.image(album: id, pixels: 96) }
            }
            guard let img, let rgb = Self.average(img) else { return }
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

#Preview {
    let records = PreviewData.snapshot.albums.map { VinylRecord.album($0, PreviewData.snapshot) }
    RoomShelfStrip(records: records, spine: CGSize(width: 34, height: 220), raise: 15, heldID: nil, playingID: records.first?.id,
                   tint: .orange, frames: SleeveFrames(), pull: { _ in }, edit: {}, remove: { _ in }, arrange: { _ in })
        .frame(height: 250).padding().background(.black)
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
