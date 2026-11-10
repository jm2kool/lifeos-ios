import SwiftData
import SwiftUI

/// Demo mode, for the simulator recordings CI makes (`LINER_DEMO=1`): a made-up library, covers and play
/// history in place of Apple Music, and `LINER_SCENE` choosing what happens on screen. Never on otherwise.
enum Demo {
    private static let env = ProcessInfo.processInfo.environment
    static let isOn = env["LINER_DEMO"] == "1"
    /// splash, crate, player, lyrics, share, stats, recap, library or island.
    static let scene = isOn ? (env["LINER_SCENE"] ?? "splash") : ""

    /// Whether the opening animation plays before the scene.
    static var showsSplash: Bool { !isOn || scene == "splash" }
    /// Whether the scene starts with a song playing.
    static var plays: Bool { ["player", "lyrics", "share", "island"].contains(scene) }

    /// Before the first view: settings for the scene, then covers, artist photos, lyrics and play history.
    @MainActor static func prepare() {
        guard isOn else { return }
        let d = UserDefaults.standard
        d.set(true, forKey: "musicConnected")
        d.set(false, forKey: "vinylMode")
        d.set(false, forKey: "playerVinyl")
        d.set(true, forKey: "openPlayerOnPlay")
        d.set(scene == "recap" ? "Recaps" : "Overview", forKey: "stats.page")
        d.set(["stats", "recap"].contains(scene) ? "stats" : scene == "library" ? "library" : "home", forKey: "root.tab")
        drawArtwork()
        let context = Store.shared.context
        let lyricsID = "lib-\(DemoLibrary.nowPlayingID)"
        let existing = (try? context.fetch(FetchDescriptor<LyricsCache>(predicate: #Predicate { $0.itemID == lyricsID }))) ?? []
        if existing.isEmpty { context.insert(LyricsCache(itemID: lyricsID, lrc: DemoLibrary.lyrics, plain: nil)) }
        Store.shared.save()
        if !d.bool(forKey: "demo.seeded") {
            DebugSeeder.seed(DemoLibrary.snapshot)
            d.set(true, forKey: "demo.seeded")
        }
    }

    /// Draws every cover and artist photo once and stores them where real artwork would be.
    @MainActor private static func drawArtwork() {
        guard !UserDefaults.standard.bool(forKey: "demo.art.v1") else { return }
        for (i, e) in DemoLibrary.entries.enumerated() {
            let cover = ImageRenderer(content: DemoCover(e).frame(width: 1400, height: 1400))
            cover.scale = 1
            if let img = cover.uiImage { ArtworkCache.shared.seed(img, album: DemoLibrary.albumID(i)) }
        }
        var done = Set<String>()
        for e in DemoLibrary.entries where done.insert(e.artist).inserted {
            let photo = ImageRenderer(content: DemoPortrait(colours: e.colours.map(Color.init(hex:))).frame(width: 800, height: 800))
            photo.scale = 1
            if let img = photo.uiImage { ArtistImageStore.shared.seed(img, for: e.artist) }
        }
        UserDefaults.standard.set(true, forKey: "demo.art.v1")
    }

    /// After launch: start the song, or switch to Vinyl Mode, as the scene asks.
    @MainActor static func run(player: PlaybackCoordinator) async {
        guard isOn else { return }
        if plays {
            _ = try? await ToneMaker.make()
            try? await Task.sleep(for: .seconds(0.8))
            let snap = DemoLibrary.snapshot
            guard let album = snap.album(DemoLibrary.albumID(0)) else { return }
            player.play(songs: snap.songs(album.songIDs))
            try? await Task.sleep(for: .seconds(0.4))
            player.seek(to: 38)
        } else if scene == "crate" {
            try? await Task.sleep(for: .seconds(2.2))
            UserDefaults.standard.set(true, forKey: "vinylMode")
        }
    }

    /// The full player opened: show lyrics or the share card, or turn the cover into a record.
    @MainActor static func playerOpened(open: (FullPlayerView.PlayerSheet) -> Void, record: () -> Void) async {
        guard isOn else { return }
        switch scene {
        case "player":
            try? await Task.sleep(for: .seconds(4.5))
            record()
        case "lyrics":
            try? await Task.sleep(for: .seconds(1.5))
            open(.lyrics)
        case "share":
            try? await Task.sleep(for: .seconds(1.5))
            open(.share)
        default: break
        }
    }

    /// Recap story mode: moves on a card every couple of seconds, as if tapped.
    @MainActor static func advanceStory(_ next: () -> Void) async {
        guard scene == "recap" else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.4))
            next()
        }
    }
}

extension View {
    /// In the named demo scene, scrolls slowly down by `distance` points after `delay` seconds.
    func demoScroll(_ scene: String, to distance: CGFloat, after delay: Double = 2) -> some View {
        modifier(DemoScroll(active: Demo.scene == scene, distance: distance, delay: delay))
    }
}

/// See `demoScroll`.
private struct DemoScroll: ViewModifier {
    let active: Bool
    let distance: CGFloat
    let delay: Double
    @State private var position = ScrollPosition(edge: .top)

    @ViewBuilder func body(content: Content) -> some View {
        if active {
            content
                .scrollPosition($position)
                .task {
                    try? await Task.sleep(for: .seconds(delay))
                    withAnimation(.easeInOut(duration: 3.5)) { position.scrollTo(y: distance) }
                }
        } else {
            content
        }
    }
}

#Preview {
    ScrollView { VStack { ForEach(0..<6, id: \.self) { DemoCover(DemoLibrary.entries[$0]).frame(width: 200) } } }
        .demoScroll("splash", to: 400)
        .background(.black)
        .environment(PreviewData.library)
}
