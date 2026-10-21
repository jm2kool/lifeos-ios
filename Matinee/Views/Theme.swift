import SwiftUI
import UIKit

enum Theme {
    static let bg = Color.black                                   // true OLED black
    static let card = Color(white: 0.07)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.24)  // marquee orange
    static let star = Color(red: 1.0, green: 0.74, blue: 0.18)    // amber
    static let heart = Color(red: 1.0, green: 0.36, blue: 0.47)
    static let watch = Color(red: 0.32, green: 0.83, blue: 0.55)
    static let list = Color(red: 0.42, green: 0.62, blue: 1.0)
    static let dim = Color.white.opacity(0.55)
}

// MARK: - Images

@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    init() { cache.totalCostLimit = 120 << 20 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if let t = inflight[url] { return await t.value }
        let t = Task<UIImage?, Never> {
            guard let (data, _) = try? await Catalog.session.data(from: url), let img = UIImage(data: data) else { return nil }
            return await img.byPreparingForDisplay() ?? img
        }
        inflight[url] = t
        let img = await t.value
        inflight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL, cost: Int(img.size.width * img.size.height * 4)) }
        return img
    }
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle().fill(Theme.card)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageStore.shared.cached(url) { image = hit; return }
            let img = await ImageStore.shared.load(url)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        }
    }
}

/// A poster with Letterboxd-style 2:3 proportions. Fetches its own artwork if the ref has none.
struct PosterView: View {
    let film: FilmRef
    var width: CGFloat? = nil
    var corner: CGFloat = 8
    var showTitleFallback = true
    var glows = true
    @State private var fetched: URL?
    @State private var glow: Color?
    @Environment(Library.self) private var library

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.card)
            if film.poster == nil && fetched == nil && showTitleFallback {
                Text(film.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6)).padding(6)
            }
            RemoteImage(url: film.poster ?? fetched).opacity(film.poster ?? fetched == nil ? 0 : 1)
        }
        .aspectRatio(2/3, contentMode: .fit)
        .frame(width: width)
        .clipShape(.rect(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Theme.line, lineWidth: 0.5))
        // Each poster casts a soft halo in its own colour.
        .shadow(color: (glow ?? .clear).opacity(0.55), radius: max(6, (width ?? 90) * 0.14), y: max(2, (width ?? 90) * 0.05))
        .task(id: film.poster ?? fetched) {
            guard glows, let url = film.poster ?? fetched else { return }
            if let hit = Palette.cached(url) { glow = hit.glow; return }
            if let p = await Palette.of(url) { withAnimation(.easeOut(duration: 0.5)) { glow = p.glow } }
        }
        .task(id: film.id) {
            guard film.poster == nil else { return }
            if let d = try? await Catalog.detail(film.id) {
                fetched = d.ref.poster
                library.hydrate(film, with: d)
            }
        }
        .accessibilityLabel(film.title)
    }
}

// MARK: - Stars

/// Tap or drag across the stars to rate in half steps; tap the current rating again to clear it.
struct StarRating: View {
    let rating: Double?
    var size: CGFloat = 34
    var spacing: CGFloat = 6
    var onChange: ((Double?) -> Void)? = nil
    @State private var dragValue: Double?

    private var shown: Double { dragValue ?? rating ?? 0 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { i in
                let v = shown - Double(i - 1)
                Image(systemName: v >= 1 ? "star.fill" : v >= 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(v >= 0.5 ? Theme.star : Color.white.opacity(0.22))
                    .frame(width: size, height: size)
                    .scaleEffect(dragValue != nil && Int(ceil(shown)) == i ? 1.15 : 1)
            }
        }
        .animation(.snappy(duration: 0.18), value: shown)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard onChange != nil else { return }
                let v = value(at: g.location.x)
                if v != dragValue { dragValue = v; UISelectionFeedbackGenerator().selectionChanged() }
            }
            .onEnded { g in
                guard onChange != nil else { return }
                let v = value(at: g.location.x)
                dragValue = nil
                if g.translation.width.magnitude < 4, v == rating { onChange?(nil) } else { onChange?(v) }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue(rating.map { "\($0.formatted()) stars" } ?? "Not rated")
        .accessibilityAdjustableAction { dir in
            let r = rating ?? 0
            switch dir {
            case .increment: onChange?(min(5, r + 0.5))
            case .decrement: onChange?(max(0.5, r - 0.5))
            @unknown default: break
            }
        }
    }

    private func value(at x: CGFloat) -> Double {
        let total = size * 5 + spacing * 4
        let clamped = min(max(x, 0), total)
        let raw = Double(clamped / total) * 5
        return max(0.5, min(5, (raw * 2).rounded(.up) / 2))
    }
}

struct SmallStars: View {
    let rating: Double?
    var body: some View {
        if let r = rating, r > 0 {
            Text(Stars.text(r)).font(.caption.weight(.semibold)).foregroundStyle(Theme.star)
        }
    }
}

// MARK: - Layout helpers

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.dim) }
            }
            Spacer()
            trailing.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 20)
    }
}
extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// A horizontally scrolling row of posters that opens the film on tap.
struct PosterRow: View {
    let films: [FilmRef]
    var width: CGFloat = 112
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(films) { f in
                    NavigationLink(value: f) { PosterView(film: f, width: width) }
                        .buttonStyle(.plain)
                        .filmContextMenu(f)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

struct PosterGrid: View {
    let films: [FilmRef]
    var columns = 4
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(films) { f in
                NavigationLink(value: f) { PosterView(film: f, corner: 6) }.buttonStyle(.plain).filmContextMenu(f)
            }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: { Text(message) }
        .foregroundStyle(.white)
    }
}

/// Long-press any poster for quick actions — the fastest way to log, like or save.
struct FilmContextMenu: ViewModifier {
    let film: FilmRef
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { router.sheet = .log(film, nil) } label: { Label("Log or review…", systemImage: "plus.circle") }
            Button { library.toggleWatched(film) } label: {
                Label(library.isWatched(film.id) ? "Remove from watched" : "Mark as watched", systemImage: library.isWatched(film.id) ? "eye.slash" : "eye")
            }
            Button { library.toggleLike(film) } label: {
                Label(library.isLiked(film.id) ? "Unlike" : "Like", systemImage: library.isLiked(film.id) ? "heart.slash" : "heart")
            }
            Button { library.toggleWatchlist(film) } label: {
                Label(library.inWatchlist(film.id) ? "Remove from watchlist" : "Add to watchlist", systemImage: library.inWatchlist(film.id) ? "clock.badge.xmark" : "clock")
            }
            Button { router.sheet = .addToList(film) } label: { Label("Add to list…", systemImage: "text.badge.plus") }
        } preview: {
            PosterView(film: film, width: 220, corner: 12).environment(library)
        }
    }
}
extension View {
    func filmContextMenu(_ f: FilmRef) -> some View { modifier(FilmContextMenu(film: f)) }

    /// Pure black page background that reaches behind the bars.
    func oledBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}

struct ToastView: View {
    let toast: Toast
    var onUndo: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol).foregroundStyle(Theme.accent)
            Text(toast.text).font(.subheadline.weight(.semibold)).lineLimit(1)
            if toast.undo {
                Button("Undo", action: onUndo).font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// A film's title drawn as its official logo, always in colour, or as text when there's no logo.
struct TitleArt: View {
    let title: String
    let logo: URL?
    var aspect: Double = 3
    var maxWidth: CGFloat = 270
    var maxHeight: CGFloat = 110
    var fontSize: CGFloat = 38
    /// The artwork the logo sits on; plain white or black logos take their colour from it.
    var poster: URL? = nil
    @State private var image: UIImage?
    @State private var ink: Palette.LogoInk = .colour
    @State private var tint: Color = Theme.accent
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                let w = min(maxWidth, maxHeight * aspect)
                logoImage(image)
                    .frame(width: w, height: w / max(aspect, 0.1))
                    .transition(.opacity)
            } else if logo == nil || failed {
                Text(title.isEmpty ? " " : title)
                    .font(.system(size: fontSize, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
            } else {
                Color.clear.frame(width: 1, height: maxHeight * 0.7)
            }
        }
        // A tight dark edge plus a soft halo keeps any logo readable over bright artwork.
        .shadow(color: .black.opacity(ink == .darkColour ? 0 : 0.55), radius: 2, y: 1)
        .shadow(color: ink == .darkColour ? .white.opacity(0.45) : .black.opacity(0.5), radius: 16, y: 3)
        .accessibilityLabel(title)
        .task(id: "\(logo?.absoluteString ?? "")|\(poster?.absoluteString ?? "")") {
            failed = false
            guard let logo else { image = nil; return }
            // Work out the colour before showing the logo, so it never flashes white and then changes.
            async let loaded = ImageStore.shared.load(logo)
            let palette = await Palette.of(poster)
            let img = await loaded
            guard let img else { image = nil; failed = true; return }
            let kind = Palette.logoInk(img)
            var t = Theme.accent
            if let palette {
                var sat: CGFloat = 0
                palette.accentUI.getHue(nil, saturation: &sat, brightness: nil, alpha: nil)
                if sat > 0.15 { t = palette.highlight }
            }
            if image == nil {
                ink = kind; tint = t
                withAnimation(.easeOut(duration: 0.3)) { image = img }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { ink = kind; tint = t; image = img }
            }
        }
    }

    /// Coloured logos keep their own colours. Plain white ones are dyed with the poster's colour
    /// (keeping their shading), plain dark ones are redrawn in it, so every title is in colour.
    @ViewBuilder private func logoImage(_ img: UIImage) -> some View {
        switch ink {
        case .colour, .darkColour:
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
        case .light:
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).colorMultiply(tint)
        case .dark:
            Image(uiImage: img).renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(tint)
        }
    }
}

/// A capsule or circle of Liquid Glass, used for buttons where the stock glass style misbehaves.
struct GlassChip<Label: View>: View {
    var prominent = false
    var circle = false
    let action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button(action: action) {
            label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, circle ? 0 : 20)
                .frame(minWidth: 46, minHeight: 46)
                .contentShape(circle ? AnyShape(Circle()) : AnyShape(Capsule()))
                .glassEffect(prominent ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                             in: circle ? AnyShape(Circle()) : AnyShape(Capsule()))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Ambient glow

/// Soft, slow-moving washes of colour pulled from the posters on screen, over OLED black.
struct AmbientGlow: View {
    let urls: [URL]
    var intensity: Double = 0.38
    @State private var colors: [Color] = []

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let spots: [CGPoint] = [CGPoint(x: w * 0.15, y: g.size.height * 0.12), CGPoint(x: w * 0.95, y: g.size.height * 0.38),
                                    CGPoint(x: w * 0.2, y: g.size.height * 0.78)]
            ZStack {
                Color.black
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { i, c in
                    Circle()
                        .fill(c)
                        .frame(width: w * 1.05, height: w * 1.05)
                        .position(spots[i])
                        .blur(radius: 110)
                        .opacity(intensity)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: urls) {
            var out: [Color] = []
            for u in urls.prefix(3) {
                var p = Palette.cached(u)
                if p == nil { p = await Palette.of(u) }
                if let p { out.append(p.glow) }
            }
            withAnimation(.easeInOut(duration: 1.2)) { colors = out }
        }
    }
}

extension View {
    /// OLED black with a glow taken from these posters.
    func ambientBackground(_ films: [FilmRef], intensity: Double = 0.38) -> some View {
        background(AmbientGlow(urls: films.compactMap(\.poster).prefix(3).map { $0 }, intensity: intensity))
            .scrollContentBackground(.hidden)
    }
}
