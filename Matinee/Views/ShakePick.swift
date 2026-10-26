import SwiftUI
import UIKit

// MARK: - Shake to pick

extension Notification.Name {
    static let deviceDidShake = Notification.Name("MatineeDeviceDidShake")
}

/// Shakes reach the window at the end of the responder chain; pass them on to SwiftUI as a notification.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

/// Your watchlist, shuffled into a swipe deck. Swipe left to see the next pick, right (or tap) and the card
/// grows into its page; ↺ brings back the last one. Choose movies or shows at the top; tap outside to close.
struct RandomPickDeck: View {
    let films: [FilmRef]
    var onClose: () -> Void
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var appeared = false
    @State private var expanded = false

    private var kind: Binding<MediaFilter> {
        Binding(get: { router.randomKind }, set: { router.randomKind = $0; router.deal(library) })
    }

    var body: some View {
        GeometryReader { geo in
            let cardH = max(240, min(min(300, geo.size.width - 64) * 1.5, geo.size.height - 380))
            let cardW = cardH / 1.5
            ZStack {
                Color.black.opacity(expanded ? 1 : 0.85)
                    .onTapGesture { if !expanded { onClose() } }
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Text("FROM YOUR WATCHLIST")
                            .font(.caption.weight(.heavy)).tracking(1.4).foregroundStyle(Theme.accent)
                        MediaFilterBar(selection: kind, options: [.movies, .shows])
                    }
                    .opacity(expanded ? 0 : 1)
                    stack(cardW: cardW, cardH: cardH, full: geo.size)
                    VStack(spacing: 12) {
                        if index < films.count { buttons }
                        Text(hint).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        if router.randomKind == .movies { timeFilter }
                    }
                    .opacity(expanded ? 0 : 1)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.3), value: index)
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true } }
        .onChange(of: router.randomDeckID) { _, _ in
            drag = .zero
            index = 0
        }
    }

    private var hint: String {
        if router.randomPickSearching && films.count <= index { return "Finding films that fit…" }
        if films.isEmpty { return "Nothing to pick from yet" }
        return index < films.count ? "Swipe left for another · right or tap to open" : "Shake to shuffle again"
    }

    // MARK: Cards

    @ViewBuilder private func stack(cardW: CGFloat, cardH: CGFloat, full: CGSize) -> some View {
        ZStack {
            if index >= films.count {
                endCard.frame(width: cardW, height: cardH)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            ForEach(Array(films.enumerated().filter { $0.offset >= index && $0.offset < index + 3 }.reversed()), id: \.element.id) { i, f in
                let depth = CGFloat(i - index)
                let top = depth == 0
                PickCard(film: f, expanded: top && expanded, lean: top ? drag.width : 0)
                    .frame(width: top && expanded ? full.width : cardW, height: top && expanded ? full.height : cardH)
                    .scaleEffect(top ? 1 : 1 - depth * 0.05)
                    .offset(y: top ? 0 : depth * 14)
                    .offset(top ? drag : .zero)
                    .rotationEffect(.degrees(top ? Double(drag.width / 22) : 0), anchor: .bottom)
                    .opacity(expanded && !top ? 0 : 1)
                    .zIndex(-depth)
                    .allowsHitTesting(top && !expanded)
                    .gesture(dragGesture(f))
                    .onTapGesture { open(f) }
            }
        }
        .frame(width: expanded ? full.width : cardW, height: expanded ? full.height : cardH)
    }

    private var endCard: some View {
        VStack(spacing: 14) {
            Text(films.isEmpty ? (router.randomKind == .shows ? "📺" : "🎬") : "🍿").font(.system(size: 54))
            if films.isEmpty && router.randomPickSearching {
                ProgressView().tint(.white)
            } else if films.isEmpty {
                Text(router.randomKind == .shows ? "No shows on your watchlist" : "No films that fit")
                    .font(.headline).multilineTextAlignment(.center)
                Text(router.randomKind == .shows ? "Save a few shows and they'll turn up here." : "Try a different length, or switch to shows.")
                    .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            } else {
                Text("That's all \(films.count)").font(.title3.weight(.bold))
                Text("You've been through every pick.").font(.subheadline).foregroundStyle(Theme.dim)
                Button("Shuffle again", systemImage: "shuffle") { router.deal(library) }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private var buttons: some View {
        HStack(spacing: 22) {
            roundButton("arrow.uturn.backward", size: 48, color: .white.opacity(index > 0 ? 0.85 : 0.3)) { rewind() }
                .disabled(index == 0)
                .accessibilityLabel("Previous pick")
            roundButton("xmark", size: 60, color: .white) { skip() }
                .accessibilityLabel("Another pick")
            roundButton("play.fill", size: 60, color: Theme.accent) { if films.indices.contains(index) { open(films[index]) } }
                .accessibilityLabel("Open this one")
        }
    }

    private func roundButton(_ symbol: String, size: CGFloat, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }

    // MARK: Swiping

    private func dragGesture(_ f: FilmRef) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                let predicted = v.predictedEndTranslation.width
                let x = abs(predicted) > abs(v.translation.width) ? predicted : v.translation.width
                if abs(v.translation.width) > 110 || abs(predicted) > 380 {
                    if x < 0 { skip() } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = .zero }
                        open(f)
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    /// The top card flies off to the left and the next one comes up.
    private func skip() {
        guard index < films.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeIn(duration: 0.22)) { drag = CGSize(width: -700, height: drag.height + 40) }
        Task {
            try? await Task.sleep(for: .milliseconds(230))
            drag = .zero
            index += 1
        }
    }

    /// The last card you skipped slides back in from the left.
    private func rewind() {
        guard index > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { drag = CGSize(width: -700, height: 0); index -= 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { drag = .zero }
        }
    }

    /// Grow the card to fill the screen, slip the film's page in underneath without a push animation,
    /// then fade the card away so the page's own poster takes over.
    private func open(_ film: FilmRef) {
        guard !expanded else { return }
        router.randomPickOpening = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.smooth(duration: 0.45)) { expanded = true }
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { router.open(film) }
            try? await Task.sleep(for: .seconds(0.3))
            onClose()
        }
    }

    /// How long have you got? Re-deals from films that fit.
    private var timeFilter: some View {
        let options: [(String, Int?)] = [("Any length", nil), ("Under 1h45", 105), ("Under 2h15", 135)]
        return HStack(spacing: 8) {
            ForEach(options, id: \.0) { label, minutes in
                let on = router.randomMaxMinutes == minutes
                Button {
                    router.randomMaxMinutes = minutes
                    UISelectionFeedbackGenerator().selectionChanged()
                    router.deal(library)
                } label: {
                    Text(label).font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? Theme.accent.opacity(0.35) : Color.white.opacity(0.08), in: .capsule)
                        .overlay(Capsule().strokeBorder(on ? Theme.accent : .clear, lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            if router.randomPickSearching { ProgressView().controlSize(.small).tint(.white) }
        }
    }
}

/// One random pick: the textless poster, the title logo, and NEXT / THIS ONE stamps as you drag.
private struct PickCard: View {
    let film: FilmRef
    var expanded = false
    var lean: CGFloat = 0
    @State private var art: FilmArt?
    @State private var artLoaded = false
    @State private var detail: FilmDetail?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay { RemoteImage(url: art?.poster ?? film.largePoster ?? film.poster) }
                .clipped()
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.75), location: 0.8),
                                   .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
                .opacity(expanded ? 0 : 1)
            VStack(spacing: 8) {
                TitleArt(title: film.title, logo: art?.logo, aspect: art?.logoAspect ?? 3, maxWidth: 240, maxHeight: 90, fontSize: 32,
                         ready: artLoaded)
                HStack(spacing: 6) {
                    Text(film.yearText)
                    if let g = detail?.genres.prefix(2), !g.isEmpty { Text("·"); Text(g.joined(separator: ", ")) }
                    if let n = detail?.regularSeasons.count, film.isShow, n > 0 { Text("·"); Text(n == 1 ? "1 season" : "\(n) seasons") }
                    else if let m = detail?.runtimeMinutes, m > 0 { Text("·"); Text(filmClock(TimeInterval(m * 60))) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
            .opacity(expanded ? 0 : 1)

            stamp("THIS ONE", color: Theme.accent, angle: -14).opacity(Double(max(0, min(1, lean / 90))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(26)
            stamp("NEXT", color: .white, angle: 14).opacity(Double(max(0, min(1, -lean / 90))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(26)
        }
        .clipShape(.rect(cornerRadius: expanded ? 0 : 32))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 0 : 32).strokeBorder(Theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .contentShape(.rect(cornerRadius: 32))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(film.title), from your watchlist. Opens the \(film.isShow ? "show" : "film").")
        .task(id: film.id) {
            let a = await Catalog.art(film.id)
            withAnimation(.easeOut(duration: 0.3)) { art = a; artLoaded = true }
            detail = try? await Catalog.detail(film.id)
        }
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }
}
