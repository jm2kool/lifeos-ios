import SwiftUI
import WebKit

/// The trailer, full screen and playing straight away. Tap ✕ to go back to the film.
struct TrailerView: View {
    let key: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            YouTubePlayer(key: key).ignoresSafeArea(edges: .bottom)
            HStack(spacing: 10) {
                if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
                    }
                    .accessibilityLabel("Open in YouTube")
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).contentShape(Circle()).glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close trailer")
            }
            .padding(.trailing, 16).padding(.top, 8)
        }
        .statusBarHidden()
        .accessibilityLabel("\(title) trailer")
    }
}

/// YouTube's embedded player. Loaded from an https base URL so YouTube sees a referrer
/// (without one, embeds refuse to play with "error 153").
struct YouTubePlayer: UIViewRepresentable {
    let key: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}
        .wrap{position:absolute;top:50%;left:0;width:100%;transform:translateY(-50%);aspect-ratio:16/9}
        iframe{width:100%;height:100%;border:0}</style></head><body><div class="wrap">
        <iframe src="https://www.youtube.com/embed/\(key)?autoplay=1&playsinline=1&rel=0&modestbranding=1&fs=1"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe></div></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://matinee.jm2kool.app"))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// Where to watch in your country (Settings → Film data): streaming, free, rent and buy, each opening the service.
struct WatchProvidersSection: View {
    let film: FilmRef
    var surface: Color = Theme.card
    @State private var providers: WatchProviders?
    @State private var loaded = false
    @Environment(\.openURL) private var openURL
    @Environment(Library.self) private var library
    @AppStorage(Catalog.regionKey) private var chosenRegion = ""

    private var region: String { Catalog.watchRegion }
    private var place: String { Catalog.regionName(region) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Where to watch", subtitle: yours.isEmpty ? "In \(place)" : "On \(yours.prefix(2).map(\.name).joined(separator: " and ")) — yours")
            Group {
                if let p = providers, !p.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        row("Stream", p.stream)
                        row("Free", p.free)
                        row("Rent", p.rent)
                        row("Buy", p.buy)
                        Text("Availability from JustWatch").font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }
                } else if loaded {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Not streaming, renting or selling in \(place) right now.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        if let u = justWatch {
                            Button { openURL(u) } label: { Label("Check JustWatch for updates", systemImage: "magnifyingglass") }
                                .buttonStyle(.glass).controlSize(.small)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 16)
        }
        .task(id: "\(film.id)|\(chosenRegion)") {
            providers = await Catalog.providers(film.id, region: region)
            loaded = true
        }
    }

    /// Your services that carry it to watch now.
    private var yours: [WatchProvider] { providers?.onServices(Set(library.services)) ?? [] }

    /// JustWatch's own search, in your country (it calls the UK "uk").
    private var justWatch: URL? {
        let cc = region == "GB" ? "uk" : region.lowercased()
        return URL(string: "https://www.justwatch.com/\(cc)/search?q=\(film.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }

    @ViewBuilder private func row(_ label: String, _ list: [WatchProvider]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(.white.opacity(0.6))
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        // Services you pay for come first, with a tick.
                        let mine = Set(library.services)
                        ForEach(list.filter { mine.contains($0.id) } + list.filter { !mine.contains($0.id) }) { p in
                            Button { open(p) } label: {
                                VStack(spacing: 5) {
                                    RemoteImage(url: p.logo).frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 12))
                                        .overlay(alignment: .bottomTrailing) {
                                            if mine.contains(p.id) {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, Theme.watch)
                                                    .offset(x: 5, y: 5)
                                            }
                                        }
                                    Text(p.name).font(.caption2.weight(.semibold)).lineLimit(1).frame(width: 64)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(label) on \(p.name)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private func open(_ p: WatchProvider) {
        if let u = p.searchURL(for: film.title) ?? providers?.link ?? justWatch { openURL(u) }
    }
}
