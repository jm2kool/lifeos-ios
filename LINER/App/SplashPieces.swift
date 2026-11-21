import SwiftUI

/// The record in the opening: grooves, a light that stays put while it turns, and your most played cover as the
/// label (the app icon's record before there is one). Drawn at any size, down to a full stop.
struct SplashRecord: View {
    let label: UIImage?
    let spin: Double
    /// Shrunk to a full stop: just the black disc and a hint of label.
    var small = false

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                ZStack {
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.06)))
                        guard r > 30 else { return }
                        var radius = r * 0.97
                        var i = 0
                        while radius > r * 0.36 {
                            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                                       with: .color(.white.opacity(i % 2 == 0 ? 0.05 : 0.022)), lineWidth: max(0.5, r * 0.004))
                            radius -= r * 0.011
                            i += 1
                        }
                    }
                    Group {
                        if let label { Image(uiImage: label).resizable().scaledToFill() } else { Image("Logo").resizable().scaledToFill() }
                    }
                    .frame(width: d * 0.36, height: d * 0.36)
                    .clipShape(Circle())
                    .opacity(small ? 0.0 : 1)
                    Circle().fill(.black).frame(width: d * 0.03, height: d * 0.03).opacity(small ? 0 : 1)
                }
                .rotationEffect(.degrees(spin))
                if !small { RecordSheen() }
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            // As a full stop it turns white like the letters.
            .overlay(Circle().fill(.white).opacity(small ? 1 : 0))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

/// A tonearm in the top right corner of its frame: the pivot, the arm, and the headshell with the needle.
struct Tonearm: View {
    /// The needle on the record (the headshell dips a little).
    var down: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pivot = CGPoint(x: w * 0.97, y: h * 0.06)
            let elbow = CGPoint(x: w * 0.88, y: h * 0.62)
            let head = CGPoint(x: w * 0.66, y: h * 0.8)
            ZStack {
                Path { p in
                    p.move(to: pivot)
                    p.addLine(to: elbow)
                    p.addLine(to: head)
                }
                .stroke(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.5)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round, lineJoin: .round))
                RoundedRectangle(cornerRadius: w * 0.012)
                    .fill(Color(white: 0.75))
                    .frame(width: w * 0.12, height: w * 0.06)
                    .rotationEffect(.degrees(-35))
                    .position(head)
                    .scaleEffect(down ? 0.94 : 1, anchor: UnitPoint(x: head.x / w, y: head.y / h))
                Circle().fill(Color(white: 0.3)).frame(width: w * 0.12).overlay(Circle().stroke(Color(white: 0.6), lineWidth: 1))
                    .position(pivot)
            }
            .shadow(color: .black.opacity(down ? 0.4 : 0.7), radius: down ? 3 : 10, x: down ? 2 : 8, y: down ? 3 : 12)
        }
        .accessibilityHidden(true)
    }
}

/// Your most played album's cover, kept for the opening's record label (so it's there before the library loads).
enum SplashCover {
    private static var file: URL { URL.applicationSupportDirectory.appending(path: "LINER/splash-label.jpg") }

    static func load() -> UIImage? { UIImage(contentsOfFile: file.path(percentEncoded: false)) }

    /// Saves the cover of the album you've played most.
    @MainActor static func update(_ snapshot: LibrarySnapshot) async {
        guard let top = snapshot.albums.filter({ !$0.isSingle }).max(by: { $0.playCount < $1.playCount }) else { return }
        let key = "splash.labelAlbum"
        if UserDefaults.standard.object(forKey: key) as? Int64 == Int64(bitPattern: top.id), load() != nil { return }
        var image = CoverOverrides.shared.image(top.id)
        if image == nil { image = await ArtworkCache.shared.image(album: top.id, pixels: 500) }
        guard let data = image?.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        UserDefaults.standard.set(Int64(bitPattern: top.id), forKey: key)
    }
}

#Preview {
    ZStack {
        SplashRecord(label: nil, spin: 20).frame(width: 230, height: 230)
        Tonearm(down: true).frame(width: 230, height: 230).offset(x: 70, y: -40)
    }
    .background(.black)
}
