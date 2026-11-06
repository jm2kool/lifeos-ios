import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Instagram Stories

/// Hands a sticker and background straight to Instagram's story editor, the way Instagram documents it:
/// the pictures go on the pasteboard for a few minutes and the `instagram-stories://` link opens the editor.
enum InstagramStories {
    /// Instagram asks for a Facebook app ID as the source. Put yours in Info.plist as `MatineeFacebookAppID`;
    /// without one we send the bundle ID, which Instagram may refuse — the share sheet still works either way.
    static var sourceID: String {
        let id = (Bundle.main.object(forInfoDictionaryKey: "MatineeFacebookAppID") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return id.isEmpty ? (Bundle.main.bundleIdentifier ?? "com.jm2kool.matinee") : id
    }

    private static var url: URL? { URL(string: "instagram-stories://share?source_application=\(sourceID)") }

    /// Whether Instagram is on this phone (needs `instagram-stories` in LSApplicationQueriesSchemes).
    @MainActor static var isInstalled: Bool { url.map { UIApplication.shared.canOpenURL($0) } ?? false }

    /// Opens Instagram's story editor with a movable sticker over a background picture or a two-colour gradient.
    @MainActor @discardableResult
    static func share(sticker: UIImage?, background: UIImage?, top: UIColor, bottom: UIColor) async -> Bool {
        guard let url, isInstalled else { return false }
        var item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundTopColor": top.hex,
            "com.instagram.sharedSticker.backgroundBottomColor": bottom.hex,
        ]
        if let d = sticker?.pngData() { item["com.instagram.sharedSticker.stickerImage"] = d }
        if let d = background?.jpegData(compressionQuality: 0.92) { item["com.instagram.sharedSticker.backgroundImage"] = d }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date.now.addingTimeInterval(5 * 60)])
        return await UIApplication.shared.open(url)
    }
}

private extension UIColor {
    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

// MARK: - The look

/// How the story is dressed.
enum StoryStyle: String, CaseIterable, Identifiable {
    case glow, colour, poster
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glow: "Glow"
        case .colour: "Colour"
        case .poster: "Poster"
        }
    }
}

/// Everything a story picture needs, loaded once.
struct StoryArt {
    var poster: UIImage?
    var logo: UIImage?
    var blurred: UIImage?
    var palette: PosterPalette?

    var accent: UIColor { palette?.accentUI ?? UIColor(Theme.accent) }
    var top: UIColor { accent.adjusted(maxBrightness: 0.5, minSaturation: 0.4, minBrightness: 0.22) }
    var bottom: UIColor { accent.adjusted(maxBrightness: 0.12, minSaturation: 0.3, minBrightness: 0.03) }
    var highlight: Color { palette?.highlight ?? Theme.star }
}

/// A ticket's outline: rounded corners and a half-circle bite out of each side where it tears.
struct TicketShape: Shape {
    var tear: CGFloat
    var radius: CGFloat = 44
    var bite: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        let body = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        var bites = Path()
        bites.addEllipse(in: CGRect(x: rect.minX - bite, y: tear - bite, width: bite * 2, height: bite * 2))
        bites.addEllipse(in: CGRect(x: rect.maxX - bite, y: tear - bite, width: bite * 2, height: bite * 2))
        return body.subtracting(bites)
    }
}

/// The sticker: your film as a cinema ticket — poster above the tear, your verdict on the stub.
struct StoryTicket: View {
    let entry: LogEntry
    let logged: Bool
    let art: StoryArt
    let showReview: Bool
    let handle: String?

    static let width: CGFloat = 640

    private var review: String? {
        let r = entry.review.trimmingCharacters(in: .whitespacesAndNewlines)
        return showReview && !r.isEmpty ? r : nil
    }
    private var posterHeight: CGFloat { review == nil ? 900 : 760 }
    private var stub: Color { Color(uiColor: art.accent.adjusted(maxBrightness: 0.2, minSaturation: 0.35, minBrightness: 0.08)) }

    private var kicker: String {
        if logged { return entry.rewatch ? "REWATCHED" : "WATCHED" }
        return Library.shared.inWatchlist(entry.film.id) ? "ON MY WATCHLIST" : "RECOMMENDED"
    }

    var body: some View {
        VStack(spacing: 0) {
            posterPart.frame(width: Self.width, height: posterHeight).clipped()
            stubPart
        }
        .frame(width: Self.width)
        .background(stub)
        .clipShape(TicketShape(tear: posterHeight))
        .overlay(TicketShape(tear: posterHeight).stroke(.white.opacity(0.14), lineWidth: 2))
    }

    private var posterPart: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: art.accent)
            if let p = art.poster {
                Image(uiImage: p).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: Self.width, height: posterHeight).clipped()
            }
            LinearGradient(colors: [.clear, stub.opacity(0.7), stub], startPoint: UnitPoint(x: 0.5, y: 0.62), endPoint: .bottom)
            Group {
                if let logo = art.logo {
                    Image(uiImage: logo).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 480, maxHeight: 170)
                        .shadow(color: .black.opacity(0.7), radius: 24)
                } else {
                    Text(entry.film.title).font(.system(size: 66, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.5)
                        .shadow(color: .black.opacity(0.7), radius: 18)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 44)
        }
    }

    private var stubPart: some View {
        VStack(alignment: .leading, spacing: 26) {
            // The tear line.
            Line().stroke(style: StrokeStyle(lineWidth: 3, dash: [10, 12]))
                .foregroundStyle(.white.opacity(0.22)).frame(height: 1).padding(.horizontal, -12)

            HStack(alignment: .firstTextBaseline) {
                Text(kicker).font(.system(size: 22, weight: .heavy, design: .monospaced)).tracking(5)
                    .foregroundStyle(art.highlight)
                Spacer()
                Text(meta).font(.system(size: 22, weight: .semibold, design: .monospaced)).tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if art.logo != nil || entry.isEpisode {
                Text(titleLine).font(.system(size: 40, weight: .bold, design: .serif)).lineLimit(2).minimumScaleFactor(0.6)
            }

            if (entry.rating ?? 0) > 0 || entry.liked {
                HStack(alignment: .center, spacing: 22) {
                    if let r = entry.rating, r > 0 { rating(r) }
                    if entry.liked { Image(systemName: "heart.fill").font(.system(size: 50)).foregroundStyle(Theme.heart) }
                    if entry.rewatch { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 40, weight: .bold)).foregroundStyle(.white.opacity(0.6)) }
                }
            }

            if let review {
                HStack(alignment: .top, spacing: 14) {
                    Text("\u{201C}").font(.system(size: 96, weight: .black, design: .serif)).foregroundStyle(art.highlight)
                        .frame(height: 60, alignment: .top).offset(y: -8)
                    Text(review).font(.system(size: 32, weight: .regular, design: .serif)).italic()
                        .lineSpacing(6).lineLimit(6).truncationMode(.tail)
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 14) {
                MatineeMark().frame(width: 52, height: 52).scaleEffect(0.8).shadow(radius: 0)
                Text("Matinee").font(.system(size: 34, weight: .heavy, design: .serif))
                Spacer()
                if let handle { Text("@\(handle)").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.6)) }
            }
            .padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 48)
        .padding(.bottom, 44)
    }

    private var titleLine: String {
        var t = entry.film.title
        if let ep = entry.episodeLabel { t += " · \(ep)" }
        return t
    }

    private var meta: String {
        var parts: [String] = []
        if logged { parts.append(entry.watchedOn.formatted(.dateTime.day().month(.abbreviated).year()).uppercased()) }
        else if let y = entry.film.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func rating(_ r: Double) -> some View {
        if FilmRatingStyle.current == .stars {
            Text(Stars.text(Score.starsShown(r))).font(.system(size: 60, weight: .semibold)).foregroundStyle(Theme.star)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Score.text(r)).font(.system(size: 92, weight: .heavy, design: .rounded))
                Text("/100").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(Score.color(r))
        }
    }
}

/// A straight horizontal line, for the ticket's tear.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// The full-screen backdrop behind the ticket: the poster melted into its own colours, or just the colours.
struct StoryBackground: View {
    let art: StoryArt
    let style: StoryStyle

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(uiColor: art.top), Color(uiColor: art.bottom)], startPoint: .top, endPoint: .bottom)
            if style == .glow, let b = art.blurred {
                Image(uiImage: b).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 1080, height: 1920).clipped()
                    .opacity(0.85)
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.05), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 500, endRadius: 1200)
            }
        }
        .frame(width: 1080, height: 1920)
    }
}

/// Background and ticket in one picture, for the share sheet and for the preview.
struct StoryComposite: View {
    let background: StoryBackground
    let ticket: StoryTicket

    var body: some View {
        ZStack {
            background
            ticket.scaleEffect(1.25).shadow(color: .black.opacity(0.55), radius: 50, y: 24)
        }
        .frame(width: 1080, height: 1920)
        .clipped()
    }
}

// MARK: - Rendering

@MainActor
enum StoryRenderer {
    /// Loads the poster, logo and colours for a title.
    static func art(for film: FilmRef) async -> StoryArt {
        async let a = Catalog.art(film.id)
        let override = Library.shared.posterOverride(film.id)
        let fallback = override ?? film.largePoster ?? film.poster
        let fetched = await a
        let posterURL = override ?? fetched?.poster ?? fallback
        let poster: UIImage? = if let posterURL { await ImageStore.shared.load(posterURL) } else { nil }
        let logo: UIImage? = if let l = fetched?.logo { await ImageStore.shared.load(l) } else { nil }
        let palette = await Palette.of(posterURL)
        let blurred: UIImage? = if let poster { await blur(poster) } else { nil }
        return StoryArt(poster: poster, logo: logo, blurred: blurred, palette: palette)
    }

    static func image<V: View>(_ view: V, scale: CGFloat) -> UIImage? {
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.isOpaque = false
        return r.uiImage
    }

    /// A soft, saturated blur of the poster, done off the main thread.
    nonisolated static func blur(_ img: UIImage) async -> UIImage? {
        guard let cg = img.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let ci = CIImage(cgImage: cg)
            let small = ci.transformed(by: CGAffineTransform(scaleX: 400 / ci.extent.width, y: 400 / ci.extent.width))
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = small.clampedToExtent()
            blur.radius = 26
            let colour = CIFilter.colorControls()
            colour.inputImage = blur.outputImage?.cropped(to: small.extent)
            colour.saturation = 1.35
            colour.brightness = -0.08
            guard let out = colour.outputImage, let made = CIContext().createCGImage(out, from: small.extent) else { return nil }
            return UIImage(cgImage: made)
        }.value
    }
}

// MARK: - The sheet

/// Share a diary entry (or a film) to Instagram Stories as a ticket, with a preview and a choice of looks.
struct StoryShareSheet: View {
    let entry: LogEntry
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("storyStyle") private var style: StoryStyle = .glow
    @State private var showReview: Bool
    @State private var art: StoryArt?
    @State private var preview: UIImage?
    @State private var sending = false
    @State private var failed = false

    init(entry: LogEntry) {
        self.entry = entry
        _showReview = State(initialValue: !(entry.spoilers ?? false))
    }

    private var logged: Bool { library.doc.entries.contains { $0.id == entry.id } }
    private var hasReview: Bool { !entry.review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var handle: String? { Handle.clean(library.doc.profile.handle) }

    private func ticket(_ art: StoryArt) -> StoryTicket {
        StoryTicket(entry: entry, logged: logged, art: art, showReview: showReview && hasReview, handle: handle)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if let preview {
                        Image(uiImage: preview).resizable().aspectRatio(9 / 16, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12)))
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else {
                        RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.card)
                            .aspectRatio(9 / 16, contentMode: .fit)
                            .overlay(ProgressView())
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 30)

                VStack(spacing: 14) {
                    Picker("Look", selection: $style) {
                        ForEach(StoryStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if hasReview && style != .poster {
                        Toggle(isOn: $showReview) {
                            Label(entry.spoilers == true ? "Show my review (has spoilers)" : "Show my review", systemImage: "text.quote")
                        }
                    }

                    Button {
                        Task { await sendToInstagram() }
                    } label: {
                        Label(sending ? "Opening Instagram…" : "Share to Instagram Stories", systemImage: "camera.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(art == nil || sending)

                    if let preview {
                        ShareLink(item: Image(uiImage: preview), preview: SharePreview(entry.film.title, image: Image(uiImage: preview))) {
                            Label("Save or share elsewhere", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background {
                ZStack {
                    Color.black
                    if let art { LinearGradient(colors: [Color(uiColor: art.top).opacity(0.6), .black], startPoint: .top, endPoint: .bottom) }
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: art != nil)
            }
            .navigationTitle("Share to your story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
            }
            .alert("Couldn't open Instagram", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Instagram doesn't seem to be on this iPhone. Use Save or share elsewhere instead — the picture is ready.")
            }
        }
        .task {
            let a = await StoryRenderer.art(for: entry.film)
            withAnimation(.smooth) { art = a }
        }
        .task(id: "\(style.rawValue)|\(showReview)|\(art != nil)") {
            guard let art else { return }
            let img = composite(art)
            withAnimation(.smooth(duration: 0.3)) { preview = img }
        }
    }

    /// The finished 1080 × 1920 picture.
    private func composite(_ art: StoryArt) -> UIImage? {
        if style == .poster { return posterCard(art) }
        return StoryRenderer.image(StoryComposite(background: StoryBackground(art: art, style: style), ticket: ticket(art)), scale: 1)
    }

    private func posterCard(_ art: StoryArt) -> UIImage? {
        StoryRenderer.image(ShareCard(film: entry.film, poster: art.poster, logo: art.logo, rating: entry.rating, liked: entry.liked,
                                      tint: Color(uiColor: art.accent)), scale: 1)
    }

    private func sendToInstagram() async {
        guard let art else { return }
        sending = true
        defer { sending = false }
        let ok: Bool
        switch style {
        case .poster:
            ok = await InstagramStories.share(sticker: nil, background: posterCard(art), top: art.top, bottom: art.bottom)
        case .glow:
            ok = await InstagramStories.share(sticker: StoryRenderer.image(ticket(art), scale: 1.5),
                                              background: StoryRenderer.image(StoryBackground(art: art, style: .glow), scale: 1),
                                              top: art.top, bottom: art.bottom)
        case .colour:
            ok = await InstagramStories.share(sticker: StoryRenderer.image(ticket(art), scale: 1.5), background: nil,
                                              top: art.top, bottom: art.bottom)
        }
        if ok { dismiss() } else { failed = true }
    }
}
