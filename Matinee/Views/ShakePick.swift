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

/// Shake the phone and a random film from your watchlist lands as a card. Tap it and it grows
/// into the film's page; tap outside to put it back.
struct ShakePickView: View {
    let film: FilmRef
    var onClose: () -> Void
    @Environment(Router.self) private var router
    @State private var art: FilmArt?
    @State private var detail: FilmDetail?
    @State private var appeared = false
    @State private var expanded = false

    var body: some View {
        GeometryReader { geo in
            let cardW = min(300, geo.size.width - 64)
            ZStack {
                Color.black.opacity(expanded ? 1 : 0.65)
                    .onTapGesture { if !expanded { onClose() } }
                VStack(spacing: 18) {
                    Text("FROM YOUR WATCHLIST")
                        .font(.caption.weight(.heavy)).tracking(1.4).foregroundStyle(Theme.accent)
                        .opacity(expanded ? 0 : 1)
                    card(width: expanded ? geo.size.width : cardW, height: expanded ? geo.size.height : cardW * 1.5)
                        .onTapGesture { open() }
                    Text("Tap to open · Shake again for another")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
                        .opacity(expanded ? 0 : 1)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task(id: film.id) {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true }
            let a = await Catalog.art(film.id)
            withAnimation(.easeOut(duration: 0.3)) { art = a }
            detail = try? await Catalog.detail(film.id)
        }
    }

    private func card(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay { RemoteImage(url: art?.poster ?? film.largePoster ?? film.poster) }
                .clipped()
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.75), location: 0.8),
                                   .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
                .opacity(expanded ? 0 : 1)
            VStack(spacing: 8) {
                TitleArt(title: film.title, logo: art?.logo, aspect: art?.logoAspect ?? 3, maxWidth: 240, maxHeight: 90, fontSize: 32, poster: art?.poster ?? film.largePoster ?? film.poster)
                HStack(spacing: 6) {
                    Text(film.yearText)
                    if let g = detail?.genres.prefix(2), !g.isEmpty { Text("·"); Text(g.joined(separator: ", ")) }
                    if let m = detail?.runtimeMinutes, m > 0 { Text("·"); Text(filmClock(TimeInterval(m * 60))) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
            .opacity(expanded ? 0 : 1)
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: expanded ? 0 : 32))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 0 : 32).strokeBorder(Theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .contentShape(.rect(cornerRadius: 32))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(film.title), from your watchlist. Opens the film.")
    }

    /// Grow the card to fill the screen, slip the film's page in underneath without a push animation,
    /// then fade the card away so the page's own poster takes over.
    private func open() {
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
}
