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

// MARK: - Scores (films, 1–100)

extension Score {
    /// Red for a miss, through marquee orange and amber, to green and mint for the best.
    static let stops: [Color] = [Color(red: 0.95, green: 0.27, blue: 0.32), Theme.accent, Theme.star, Theme.watch,
                                 Color(red: 0.36, green: 0.9, blue: 0.86)]

    static func color(_ s: Double) -> Color {
        switch s {
        case ..<40: return stops[0]
        case ..<60: return stops[1]
        case ..<75: return stops[2]
        case ..<90: return stops[3]
        default: return stops[4]
        }
    }
}

/// Rate a film out of 100 by dragging round the dial. Every point ticks under your thumb, every ten
/// clicks harder; − and + nudge by one. Tap the number to clear it.
struct ScoreDial: View {
    let score: Double?
    var size: CGFloat = 200
    var onChange: ((Double?) -> Void)? = nil
    @State private var dragValue: Double?

    private let sweep = 270.0
    private let start = 135.0     // degrees, clockwise from 3 o'clock: the arc opens at the bottom
    private var line: CGFloat { size * 0.075 }
    private var shown: Double? { dragValue ?? score }
    private var fraction: Double { ((shown ?? 1) - 1) / 99 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ticks
                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(start))
                if shown != nil {
                    Circle()
                        .trim(from: 0, to: max(0.004, fraction * sweep / 360))
                        .stroke(AngularGradient(colors: Score.stops, center: .center, startAngle: .degrees(0), endAngle: .degrees(sweep)),
                                style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(start))
                        .shadow(color: Score.color(shown ?? 0).opacity(0.6), radius: 10)
                    knob
                }
                centre
            }
            .padding(line * 1.9)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(drag)
            .animation(dragValue == nil ? .snappy(duration: 0.3) : nil, value: shown)

            if onChange != nil {
                HStack(spacing: 18) {
                    nudge("minus", -1)
                    Text(shown.map(Score.word) ?? "Drag round to rate")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(shown.map(Score.color) ?? .white.opacity(0.6))
                        .frame(minWidth: 120)
                        .contentTransition(.opacity)
                    nudge("plus", 1)
                }
                .padding(.top, -size * 0.16)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Score out of 100")
        .accessibilityValue(score.map { "\(Int($0))" } ?? "Not rated")
        .accessibilityAdjustableAction { dir in
            let r = score ?? 50
            switch dir {
            case .increment: onChange?(min(100, r + 1))
            case .decrement: onChange?(max(1, r - 1))
            @unknown default: break
            }
        }
    }

    private var centre: some View {
        VStack(spacing: 0) {
            if let v = shown {
                Text("\(Int(v))")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: v))
                    .foregroundStyle(.white)
                Text("/ 100").font(.system(size: size * 0.065, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            } else {
                Image(systemName: "hand.draw").font(.system(size: size * 0.16)).foregroundStyle(.white.opacity(0.4))
                Text("RATE").font(.system(size: size * 0.065, weight: .heavy)).tracking(1.5).foregroundStyle(.white.opacity(0.45)).padding(.top, 4)
            }
        }
    }

    private var ticks: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            ForEach(0...10, id: \.self) { i in
                let a = Angle.degrees(start + sweep * Double(i) / 10).radians
                let lit = (shown ?? 0) >= Double(max(1, i * 10))
                Capsule()
                    .fill(lit ? Score.color(Double(i * 10)) : Color.white.opacity(0.18))
                    .frame(width: 2, height: i % 5 == 0 ? line * 0.9 : line * 0.55)
                    .rotationEffect(.radians(a + .pi / 2))
                    .position(x: r + cos(a) * (r + line * 1.3), y: r + sin(a) * (r + line * 1.3))
            }
        }
    }

    private var knob: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            let a = Angle.degrees(start + sweep * fraction).radians
            Circle()
                .fill(.white)
                .frame(width: line * 1.5, height: line * 1.5)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                .scaleEffect(dragValue != nil ? 1.25 : 1)
                .position(x: r + cos(a) * r, y: r + sin(a) * r)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard onChange != nil, !(dragValue == nil && isCentre(g.startLocation) && g.translation == .zero) else { return }
                let v = value(at: g.location)
                if v != dragValue {
                    if let old = dragValue, Int(old) / 10 != Int(v) / 10 { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    else { UISelectionFeedbackGenerator().selectionChanged() }
                    dragValue = v
                }
            }
            .onEnded { g in
                guard onChange != nil else { return }
                // A tap on the number clears the score; it never rates.
                if g.translation.width.magnitude < 4 && g.translation.height.magnitude < 4 && isCentre(g.location) {
                    dragValue = nil
                    if score != nil { onChange?(nil); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    return
                }
                let v = value(at: g.location)
                dragValue = nil
                onChange?(v)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    private func isCentre(_ p: CGPoint) -> Bool { hypot(p.x - size / 2, p.y - size / 2) < size * 0.28 }

    /// Angle of the touch round the dial → 1…100. Touches in the gap at the bottom stick to the nearer end.
    private func value(at p: CGPoint) -> Double {
        let deg = Double(atan2(p.y - size / 2, p.x - size / 2)) * 180 / .pi
        var rel = deg - start
        while rel < 0 { rel += 360 }
        while rel >= 360 { rel -= 360 }
        let f = rel <= sweep ? rel / sweep : (rel < sweep + (360 - sweep) / 2 ? 1 : 0)
        return (1 + f * 99).rounded()
    }

    private func nudge(_ symbol: String, _ step: Double) -> some View {
        Button {
            let v = min(100, max(1, (score ?? 50) + step))
            onChange?(v)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).frame(width: 34, height: 34)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(step > 0 ? "Up one" : "Down one")
    }
}

/// A film's score as a small coloured pill: "87".
struct ScorePill: View {
    let score: Double
    var fontSize: CGFloat = 11
    var body: some View {
        Text(Score.text(score))
            .font(.system(size: fontSize, weight: .heavy, design: .rounded)).monospacedDigit()
            .foregroundStyle(Score.color(score))
            .padding(.horizontal, fontSize * 0.45).padding(.vertical, fontSize * 0.1)
            .background(Score.color(score).opacity(0.18), in: .capsule)
    }
}

/// A rating as a score pill or in stars, whichever you picked in Settings.
struct SmallRating: View {
    let rating: Double?
    @AppStorage(FilmRatingStyle.key) private var style: FilmRatingStyle = .score
    var body: some View {
        if let r = rating, r > 0 {
            if style == .stars { SmallStars(rating: Score.starsShown(r)) }
            else { ScorePill(score: r) }
        }
    }
}

/// An average (or any worked-out rating) in your scale: "4.2 ★" or a coloured "84".
struct RatingValue: View {
    let score: Double
    var font: Font = .title3.weight(.bold)
    var symbolFont: Font = .caption
    @AppStorage(FilmRatingStyle.key) private var style: FilmRatingStyle = .score
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if style == .stars {
                Text(Score.toStars(score).formatted(.number.precision(.fractionLength(1)))).font(font).monospacedDigit()
                Image(systemName: "star.fill").font(symbolFont).foregroundStyle(Theme.star)
            } else {
                Text(Score.text(score)).font(font).monospacedDigit().foregroundStyle(Score.color(score))
            }
        }
    }
}

/// A slim 1–100 slider for tight spots: drag along the bar, tap the number to clear it.
struct ScoreBar: View {
    let score: Double?
    var onChange: ((Double?) -> Void)? = nil
    @State private var dragValue: Double?

    private var shown: Double? { dragValue ?? score }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                let w = g.size.width
                let f = CGFloat(((shown ?? 1) - 1) / 99)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 8)
                    if shown != nil {
                        // The full gradient, uncovered up to your score, so the end colour matches it.
                        Capsule().fill(LinearGradient(colors: Score.stops, startPoint: .leading, endPoint: .trailing))
                            .frame(height: 8)
                            .mask(alignment: .leading) { Capsule().frame(width: max(8, w * f), height: 8) }
                        Circle().fill(.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                            .scaleEffect(dragValue != nil ? 1.2 : 1)
                            .offset(x: min(max(0, w * f - 10), w - 20))
                    }
                }
                .frame(width: w, height: g.size.height)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard onChange != nil else { return }
                        let n = value(v.location.x, w)
                        if n != dragValue {
                            if let old = dragValue, Int(old) / 10 != Int(n) / 10 { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                            else { UISelectionFeedbackGenerator().selectionChanged() }
                            dragValue = n
                        }
                    }
                    .onEnded { v in
                        guard onChange != nil else { return }
                        dragValue = nil
                        onChange?(value(v.location.x, w))
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
            }
            .frame(height: 30)
            Text(shown.map { Score.text($0) } ?? "–")
                .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(shown.map(Score.color) ?? .white.opacity(0.4))
                .contentTransition(.numericText())
                .frame(width: 34, alignment: .trailing)
                .contentShape(.rect)
                .onTapGesture {
                    guard score != nil else { return }
                    onChange?(nil)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        }
        .animation(dragValue == nil ? .snappy(duration: 0.25) : nil, value: shown)
        .accessibilityElement()
        .accessibilityLabel("Score out of 100")
        .accessibilityValue(score.map { "\(Int($0))" } ?? "Not rated")
        .accessibilityAdjustableAction { dir in
            let r = score ?? 50
            switch dir {
            case .increment: onChange?(min(100, r + 1))
            case .decrement: onChange?(max(1, r - 1))
            @unknown default: break
            }
        }
    }

    private func value(_ x: CGFloat, _ w: CGFloat) -> Double { (1 + Double(min(max(x / max(w, 1), 0), 1)) * 99).rounded() }
}

/// Rating that fits in a row: small stars, or the slim score bar.
struct CompactRatingInput: View {
    let score: Double?
    var starSize: CGFloat = 22
    let onChange: (Double?) -> Void
    @AppStorage(FilmRatingStyle.key) private var style: FilmRatingStyle = .score
    var body: some View {
        if style == .stars {
            StarRating(rating: score.map(Score.starsShown), size: starSize, spacing: starSize * 0.2) { onChange($0.map(Score.fromStars)) }
        } else {
            ScoreBar(score: score, onChange: onChange)
        }
    }
}

/// All / Movies / Shows as a glass capsule; the selection slides between them.
struct MediaFilterBar: View {
    @Binding var selection: MediaFilter
    var options: [MediaFilter] = MediaFilter.allCases
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { m in
                let on = selection == m
                Button {
                    guard !on else { return }
                    withAnimation(.snappy(duration: 0.3)) { selection = m }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(m.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? Color.black : Color.white.opacity(0.85))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background {
                            if on { Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Rate the way you prefer: the 1–100 dial, or stars (saved as a score, 10 points per half star).
struct FilmRatingInput: View {
    let score: Double?
    var dialSize: CGFloat = 200
    var starSize: CGFloat = 36
    var showsHint = true
    let onChange: (Double?) -> Void
    @AppStorage(FilmRatingStyle.key) private var style: FilmRatingStyle = .score

    var body: some View {
        if style == .stars {
            VStack(spacing: 8) {
                StarRating(rating: score.map(Score.starsShown), size: starSize, spacing: starSize * 0.22) { onChange($0.map(Score.fromStars)) }
                if showsHint {
                    Text(score.map { "\(Stars.text(Score.starsShown($0)))  ·  \(Score.word($0))" } ?? "Slide across the stars — half stars work too")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                }
            }
        } else {
            ScoreDial(score: score, size: dialSize, onChange: onChange)
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
/// The text never flashes up first: it waits until `ready` says the logo lookup is done and found
/// nothing, the logo fails to load, or five seconds pass with no logo on screen.
struct TitleArt: View {
    let title: String
    let logo: URL?
    var aspect: Double = 3
    var maxWidth: CGFloat = 270
    var maxHeight: CGFloat = 110
    var fontSize: CGFloat = 38
    /// The artwork lookup has finished, so a nil logo means there isn't one.
    var ready = true
    @State private var image: UIImage?
    @State private var ink: Palette.LogoInk = .colour
    @State private var failed = false
    @State private var waitedTooLong = false

    /// Dark logos get a light halo instead of a dark shadow, so they read on dark pages.
    private var darkInk: Bool { ink == .dark || ink == .darkColour }

    var body: some View {
        Group {
            if let image {
                let w = min(maxWidth, maxHeight * aspect)
                // Always the studio's own artwork, in its own colours — never recoloured.
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: w, height: w / max(aspect, 0.1))
                    .transition(.opacity)
            } else if failed || waitedTooLong || (ready && logo == nil) {
                Text(title.isEmpty ? " " : title)
                    .font(.system(size: fontSize, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .transition(.opacity)
            } else {
                Color.clear.frame(width: 1, height: maxHeight * 0.7)
            }
        }
        // A tight edge plus a soft halo keeps any logo readable over bright or dark artwork.
        .shadow(color: darkInk ? .white.opacity(0.35) : .black.opacity(0.55), radius: 2, y: 1)
        .shadow(color: darkInk ? .white.opacity(0.5) : .black.opacity(0.5), radius: 16, y: 3)
        .accessibilityLabel(title)
        .task(id: logo) {
            failed = false
            guard let logo else { image = nil; return }
            guard let img = await ImageStore.shared.load(logo) else { image = nil; failed = true; return }
            let kind = Palette.logoInk(img)
            if image == nil {
                ink = kind
                withAnimation(.easeOut(duration: 0.3)) { image = img }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { ink = kind; image = img }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { waitedTooLong = true }
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
