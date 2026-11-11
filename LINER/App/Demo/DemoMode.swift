import SwiftData
import SwiftUI

/// Demo mode, for the simulator recordings CI makes (`LINER_DEMO=1`): a made-up library, covers and play
/// history in place of Apple Music, and `LINER_SCENE` choosing what happens on screen. Never on otherwise.
enum Demo {
    private static let env = ProcessInfo.processInfo.environment
    static let isOn = env["LINER_DEMO"] == "1"
    /// splash, crate, gatefold, room, player, lyrics, share, stats, recap, library or island.
    static let scene = isOn ? (env["LINER_SCENE"] ?? "splash") : ""

    /// Whether the opening animation plays before the scene.
    static var showsSplash: Bool { !isOn || scene == "splash" }
    /// Whether the scene starts with a song playing.
    static var plays: Bool { ["player", "lyrics", "share", "island"].contains(scene) }

    /// Before the first view: settings for the scene, album covers and play history.
    @MainActor static func prepare() {
        guard isOn else { return }
        let d = UserDefaults.standard
        d.set(true, forKey: "musicConnected")
        d.set(["gatefold", "room"].contains(scene), forKey: "vinylMode")
        d.set(false, forKey: "playerVinyl")
        d.set(true, forKey: "openPlayerOnPlay")
        d.set(scene == "recap" ? "Recaps" : "Overview", forKey: "stats.page")
        d.set(["stats", "recap"].contains(scene) ? "stats" : scene == "library" ? "library" : "home", forKey: "root.tab")
        for (i, e) in DemoLibrary.entries.enumerated() {
            if let url = URL(string: e.artwork) { ArtworkCache.shared.register(remote: url, for: DemoLibrary.albumID(i)) }
        }
        if !d.bool(forKey: "demo.seeded.v2") {
            seedHistory(DemoLibrary.snapshot)
            d.set(true, forKey: "demo.seeded.v2")
        }
    }

    /// Three weeks of plays, each song's share following its all-time count, so recaps rank the way the stats do.
    /// Rows are marked as seeded, like Settings → test data.
    @MainActor private static func seedHistory(_ snap: LibrarySnapshot) {
        let context = Store.shared.context
        let days = 21
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(-Double(days) * 86_400)
        UserDefaults.standard.set(start, forKey: "recaps.baseline")
        var plan: [Int: [(UInt64, Int)]] = [:]
        var totals: [UInt64: Int] = [:]
        for day in 1...days {
            for s in snap.songs {
                let n = Int((Double(s.playCount) * 0.006 * Double.random(in: 0.85...1.15)).rounded())
                guard n > 0 else { continue }
                plan[day, default: []].append((s.id, n))
                totals[s.id, default: 0] += n
            }
        }
        var counts = Dictionary(snap.songs.map { ($0.id, max(0, $0.playCount - (totals[$0.id] ?? 0))) }, uniquingKeysWith: { max($0, $1) })
        for s in snap.songs {
            let row = PlaySnapshot(date: start, persistentID: s.id, playCount: counts[s.id] ?? 0)
            row.seeded = true
            context.insert(row)
        }
        for day in 1...days {
            let date = start.addingTimeInterval(Double(day) * 86_400 - 3600)
            for (id, n) in plan[day] ?? [] {
                counts[id, default: 0] += n
                let row = PlaySnapshot(date: date, persistentID: id, playCount: counts[id] ?? 0)
                row.seeded = true
                context.insert(row)
            }
        }
        Store.shared.save()
    }

    /// After launch: start the song, or switch to Vinyl Mode, as the scene asks.
    @MainActor static func run(player: PlaybackCoordinator) async {
        guard isOn else { return }
        if plays {
            _ = try? await ToneMaker.make()
            try? await Task.sleep(for: .seconds(0.8))
            let snap = DemoLibrary.snapshot
            guard let album = snap.album(DemoLibrary.nowPlayingAlbum) else { return }
            player.play(songs: snap.songs(album.songIDs), startAt: DemoLibrary.nowPlayingTrack)
            try? await Task.sleep(for: .seconds(0.4))
            player.seek(to: 21)
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

    /// Vinyl Mode's crate is up: flip to a record and open its gatefold, or go into the Listening Room.
    @MainActor static func crateShown(records: [String], focus: (String) -> Void, open: (String) -> Void, room: () -> Void) async {
        guard isOn, records.count > 2 else { return }
        switch scene {
        case "crate":
            try? await Task.sleep(for: .seconds(1.6))
            focus(records[1])
            try? await Task.sleep(for: .seconds(1.0))
            focus(records[2])
        case "gatefold":
            try? await Task.sleep(for: .seconds(1.4))
            focus(records[1])
            try? await Task.sleep(for: .seconds(1.1))
            open(records[1])
        case "room":
            try? await Task.sleep(for: .seconds(1.0))
            room()
        default: break
        }
    }

    /// The Listening Room: take a record off the shelf, open its sleeve so the record slips out, then another.
    @MainActor static func roomShown(pull: (Int) -> Void, openSleeve: () -> Void, stow: () -> Void) async {
        guard scene == "room" else { return }
        try? await Task.sleep(for: .seconds(1.6))
        pull(0)
        try? await Task.sleep(for: .seconds(1.5))
        openSleeve()
        try? await Task.sleep(for: .seconds(3.2))
        stow()
        try? await Task.sleep(for: .seconds(1.6))
        pull(2)
        try? await Task.sleep(for: .seconds(1.5))
        openSleeve()
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
    ScrollView { VStack { ForEach(0..<20, id: \.self) { Text("Row \($0)").font(.serif(30)).frame(height: 120) } } }
        .demoScroll("splash", to: 400)
        .background(.black)
        .environment(PreviewData.library)
}
