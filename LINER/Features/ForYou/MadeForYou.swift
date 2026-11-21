import Foundation

/// LINER.'s own "Made for You": mixes built on the phone from your library and play counts, refreshed each day.
/// (Apple's personal For You needs an Apple Music account sign-in that free-signed apps can't have.)
struct MadeForYouMix: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let songIDs: [UInt64]
    var coverAlbumIDs: [UInt64] = []

    /// Today's mixes.
    static func all(_ snap: LibrarySnapshot, stats: LibraryStats) -> [MadeForYouMix] {
        let songs = snap.songs.filter { $0.duration > 30 }
        guard songs.count >= 20 else { return [] }
        var rng = DailyRandom()
        var mixes: [MadeForYouMix] = []
        func make(_ id: String, _ title: String, _ subtitle: String, _ list: [Song]) {
            guard list.count >= 8 else { return }
            var covers: [UInt64] = []
            for s in list where !covers.contains(s.albumID) && covers.count < 4 { covers.append(s.albumID) }
            mixes.append(MadeForYouMix(id: id, title: title, subtitle: subtitle, songIDs: list.map(\.id), coverAlbumIDs: covers))
        }

        // Heavy Rotation: what you've played most lately.
        let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
        let recent = songs.filter { ($0.lastPlayed ?? .distantPast) > monthAgo }.sorted { $0.playCount > $1.playCount }
        make("heavy", "Heavy Rotation", "What you keep coming back to", Array(recent.prefix(40)))

        // Daily Mixes: your top genres, favourites with a few you play less, shuffled for today.
        let genres = Dictionary(grouping: songs.filter { !$0.genre.isEmpty }, by: \.genre)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.playCount }) }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        for (i, g) in genres.enumerated() {
            let pool = songs.filter { $0.genre == g }.sorted { $0.playCount > $1.playCount }
            let favourites = Array(pool.prefix(30)).shuffled(using: &rng).prefix(18)
            let deeper = Array(pool.dropFirst(30)).shuffled(using: &rng).prefix(12)
            make("daily\(i)", "Daily Mix \(i + 1)", g, Array(favourites + deeper).shuffled(using: &rng))
        }

        // Rediscover: songs you loved but haven't played for half a year.
        let halfYear = Date.now.addingTimeInterval(-180 * 86_400)
        let old = songs.filter { $0.playCount >= 10 && ($0.lastPlayed ?? .distantPast) < halfYear }.sorted { $0.playCount > $1.playCount }
        make("rediscover", "Rediscover", "Old favourites you haven't played in a while", Array(old.prefix(50)).shuffled(using: &rng))

        // Fresh Finds: added lately and barely played yet.
        let fresh = songs.filter { $0.dateAdded > Date.now.addingTimeInterval(-60 * 86_400) && $0.playCount < 3 }.sorted { $0.dateAdded > $1.dateAdded }
        make("fresh", "Fresh Finds", "New in your library, waiting for a listen", Array(fresh.prefix(40)))

        // Your Essentials: the songs that define each of your top artists.
        for artist in stats.artists.prefix(4) {
            let top = snap.songs(of: artist).sorted { $0.playCount > $1.playCount }.prefix(25)
            make("ess-\(artist.id)", "\(artist.name): My Essentials", "Your most played \(artist.name)", Array(top))
        }
        return mixes
    }
}

/// A random sequence that stays the same all day, so mixes don't reshuffle every time you look.
struct DailyRandom: RandomNumberGenerator {
    private var state: UInt64
    init() {
        let day = UInt64(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 1)
        state = day &* 0x9E3779B97F4A7C15
    }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
