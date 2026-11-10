import Foundation

/// The made-up library for demo mode: invented artists and albums with believable play counts, so the simulator
/// recordings (and the promo video cut from them) show a lived-in LINER. without anyone's real music.
@MainActor
enum DemoLibrary {
    /// One invented album: who, what, the cover's colours and pattern, and its songs.
    struct Entry {
        let artist: String
        let title: String
        let genre: String
        let year: Int
        let colours: [UInt32]
        let style: DemoCover.Style
        let songs: [String]
        /// How much this album gets played, 0…1.
        let love: Double
    }

    static let entries: [Entry] = [
        Entry(artist: "Marlowe Vane", title: "Paper Moons", genre: "Indie Pop", year: 2025,
              colours: [0xF2A65A, 0xE4572E, 0x2E1F47, 0xF7D488], style: .sun,
              songs: ["Paper Moons", "Kerosene Summer", "Lightweight", "Postcode", "Hold the Door", "Velvet Static", "Night Bus Home", "Ribbons"], love: 1),
        Entry(artist: "SOLENNE", title: "Chrome Heart", genre: "Electronic", year: 2024,
              colours: [0x00F0FF, 0x7B2FF7, 0x0B0B2B, 0xFF4FD8], style: .rings,
              songs: ["Chrome Heart", "Satellite Kiss", "Afterhours", "Mirrorball", "Signal", "Zero Gravity", "Low Orbit"], love: 0.92),
        Entry(artist: "Ivy Okafor", title: "Saltwater Hymns", genre: "R&B", year: 2025,
              colours: [0x0F4C5C, 0x5FA8D3, 0xE9C46A, 0x1B263B], style: .mesh,
              songs: ["Saltwater", "Undertow", "Honey, Slowly", "Blue Hour", "Tides", "Lantern", "Sunday Light", "Shoreline"], love: 0.86),
        Entry(artist: "Theo Lark", title: "Wide Awake, Dreaming", genre: "Pop", year: 2025,
              colours: [0xFFB5C2, 0xFF6F91, 0x845EC2, 0xFFC75F], style: .type,
              songs: ["Wide Awake", "Sugarcoat", "Fever Dream", "Halfway Home", "Daylight Savings", "Pillow Talk", "Run It Back"], love: 0.8),
        Entry(artist: "The Night Ferry", title: "Harbour Lights", genre: "Dream Pop", year: 2023,
              colours: [0x14213D, 0xFCA311, 0x3A506B, 0xE5E5E5], style: .bars,
              songs: ["Harbour Lights", "Fog Signal", "Crossing", "Port of Call", "Lighthouse Keeper", "Deck Chairs", "Last Sailing"], love: 0.74),
        Entry(artist: "Noor", title: "Golden Hour Radio", genre: "Soul", year: 2024,
              colours: [0xD4A373, 0x9C6644, 0xFEFAE0, 0x582F0E], style: .sun,
              songs: ["Golden Hour", "Radio Love", "Static Heart", "Call Me Back", "Amber", "Late Show", "Frequency"], love: 0.7),
        Entry(artist: "Arjun Rao", title: "Monsoon Letters", genre: "Indie", year: 2023,
              colours: [0x2D6A4F, 0x95D5B2, 0x081C15, 0xD8F3DC], style: .mesh,
              songs: ["Monsoon Letters", "Chai at Four", "Rooftops", "Paper Boats", "Old City", "Monsoon Reprise"], love: 0.66),
        Entry(artist: "Kite & Harbour", title: "Northbound", genre: "Folk", year: 2022,
              colours: [0x6B705C, 0xCB997E, 0xFFE8D6, 0x3F4238], style: .bars,
              songs: ["Northbound", "Pine & Ash", "Woodsmoke", "Letters Home", "River Song", "Wintering"], love: 0.55),
        Entry(artist: "SOLENNE", title: "Midnight Index", genre: "Electronic", year: 2025,
              colours: [0xFF006E, 0x3A0CA3, 0x050505, 0xFB5607], style: .type,
              songs: ["Midnight Index", "Pulse", "Neon Rain", "Cold Open", "Afterimage", "Loop 47"], love: 0.62),
        Entry(artist: "Low Tide Club", title: "Summer Static", genre: "Alternative", year: 2021,
              colours: [0xFFBE0B, 0xFB5607, 0x3A86FF, 0xFFFFFF], style: .rings,
              songs: ["Summer Static", "Skate Park", "Sunburn", "Loud Quiet Loud", "Polaroid", "Garage Door"], love: 0.48),
        Entry(artist: "Ember Park", title: "Lights Out Lullabies", genre: "Lo-fi", year: 2022,
              colours: [0x22223B, 0x4A4E69, 0x9A8C98, 0xF2E9E4], style: .mesh,
              songs: ["Lights Out", "Rain on Glass", "3 A.M.", "Slow Tape", "Window Seat", "Goodnight, Moon"], love: 0.44),
        Entry(artist: "Marlowe Vane", title: "Glass Season", genre: "Indie Pop", year: 2021,
              colours: [0xA2D2FF, 0xBDE0FE, 0xCDB4DB, 0x22223B], style: .rings,
              songs: ["Glass Season", "First Frost", "Tangerine", "Small Hours", "Snow Globe", "Weather Report"], love: 0.58),
        Entry(artist: "Ivy Okafor", title: "Slow Bloom", genre: "R&B", year: 2022,
              colours: [0x780000, 0xC1121F, 0xFDF0D5, 0x003049], style: .type,
              songs: ["Slow Bloom", "Petals", "Gardenia", "Overgrown", "Greenhouse", "Bloom Again"], love: 0.5),
        Entry(artist: "Theo Lark", title: "Postcards", genre: "Pop", year: 2021,
              colours: [0x90E0EF, 0x0077B6, 0xFFD166, 0x03045E], style: .sun,
              songs: ["Postcards", "Wish You Were Here", "Seaside", "Lost Luggage", "Departures"], love: 0.4),
        Entry(artist: "The Night Ferry", title: "Undertow EP", genre: "Dream Pop", year: 2024,
              colours: [0x2B2D42, 0x8D99AE, 0xEF233C, 0xEDF2F4], style: .bars,
              songs: ["Undertow", "Slow Wake", "Keel", "Ballast"], love: 0.36),
        Entry(artist: "Noor", title: "Velvet Tapes", genre: "Soul", year: 2022,
              colours: [0x5F0F40, 0x9A031E, 0xFB8B24, 0xE36414], style: .rings,
              songs: ["Velvet", "Tape Hiss", "Side A", "Rewind", "B-Side Love"], love: 0.33),
    ]

    /// Album IDs start here; song IDs are album × 100 + track.
    static func albumID(_ index: Int) -> UInt64 { UInt64(7_000 + index) }

    /// The song the demo plays: track one of the first album.
    static var nowPlayingID: UInt64 { albumID(0) * 100 + 1 }

    /// The 90-second pad from the spike lab stands in for every song's audio, so LINER.'s own player can play it.
    static var toneURL: URL { LoopVideoMaker.folder.appending(path: "liner-test-tone.m4a") }

    static let snapshot: LibrarySnapshot = build()

    private static func build() -> LibrarySnapshot {
        var songs: [Song] = []
        var albums: [Album] = []
        let day = 86_400.0
        for (a, e) in entries.enumerated() {
            let id = albumID(a)
            var ids: [UInt64] = []
            for (t, title) in e.songs.enumerated() {
                let sid = id * 100 + UInt64(t + 1)
                ids.append(sid)
                // Openers and singles get played most; a little wobble so ranks look real.
                let base = 40 + e.love * 380
                let shape = t == 0 ? 1.0 : 0.45 + 0.5 / Double(t + 1)
                let wobble = Double((Int(sid) * 37) % 23) / 23.0 * 0.35 + 0.8
                let plays = Int(base * shape * wobble)
                songs.append(Song(id: sid, title: title, artist: e.artist, albumTitle: e.title, albumArtist: e.artist,
                                  albumID: id, genre: e.genre, composer: e.artist, duration: 168 + Double((Int(sid) * 53) % 110),
                                  playCount: plays, rating: max(0, 5 - t / 2), trackNumber: t + 1, discNumber: 1,
                                  dateAdded: .now.addingTimeInterval(-Double(a) * 9 * day - Double(t)),
                                  lastPlayed: .now.addingTimeInterval(-Double(a + t) * 3600),
                                  releaseDate: Calendar.current.date(from: DateComponents(year: e.year)),
                                  storeID: "", isCloudOnly: false, hasArtwork: true, assetURL: toneURL))
            }
            let mine = songs.filter { $0.albumID == id }
            albums.append(Album(id: id, title: e.title, artist: e.artist, genre: e.genre, year: e.year, songIDs: ids,
                                playCount: mine.reduce(0) { $0 + $1.playCount }, duration: mine.reduce(0) { $0 + $1.duration },
                                dateAdded: .now.addingTimeInterval(-Double(a) * 9 * day), rating: 4 + e.love))
        }
        var artists: [Artist] = []
        for name in entries.map(\.artist).uniqued() {
            let theirs = albums.filter { $0.artist == name }
            artists.append(Artist(id: MediaKey.normalise(name), name: name, albumIDs: theirs.map(\.id),
                                  songCount: theirs.reduce(0) { $0 + $1.songCount }, playCount: theirs.reduce(0) { $0 + $1.playCount },
                                  dateAdded: theirs.map(\.dateAdded).max() ?? .now, rating: 4))
        }
        let byPlays = songs.sorted { $0.playCount > $1.playCount }
        let playlists = [
            Playlist(id: 9_001, name: "Late Night Drive", songIDs: byPlays.prefix(24).map(\.id),
                     coverAlbumIDs: albums.prefix(4).map(\.id), playCount: 1_284, dateAdded: .now.addingTimeInterval(-40 * day)),
            Playlist(id: 9_002, name: "Sunday Slow", songIDs: byPlays.suffix(18).map(\.id),
                     coverAlbumIDs: albums.suffix(4).map(\.id), playCount: 412, dateAdded: .now.addingTimeInterval(-12 * day)),
        ]
        var snap = LibrarySnapshot(songs: songs, albums: albums, artists: artists, playlists: playlists)
        snap.scannedAt = .now
        return snap
    }

    /// Words for the song the demo plays (written for LINER., so they're free to show), timed from 0:40.
    static let lyrics = """
    [00:36.00] ♪
    [00:40.00] We folded the city into paper moons
    [00:44.20] Hung them over the bed in your old room
    [00:48.40] Every light on the street was a song we knew
    [00:52.60] And I played them all back to you
    [00:56.80] Oh, turn it up, let the needle fall
    [01:01.00] Every play is a postcard on the wall
    [01:05.20] Count the nights by the songs we wore
    [01:09.40] Paper moons, we were made for more
    [01:13.60] We were made for more
    [01:18.00] ♪
    """
}

private extension Array where Element: Hashable {
    /// The same order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
