import Foundation

/// The library for demo mode: real albums (Charli xcx, Drake, Doja Cat, Yeat) with made-up play counts, so the
/// simulator recordings (and the promo video cut from them) show a lived-in LINER.
@MainActor
enum DemoLibrary {
    /// One album: who, what, its songs (title, seconds) and how much it gets played (0…1). Real albums carry
    /// their Apple Music cover URL; the invented one draws its own cover.
    struct Entry {
        let artist: String
        let title: String
        let genre: String
        let year: Int
        let love: Double
        var artwork: String? = nil
        var colours: [UInt32] = []
        var style: DemoCover.Style = .sun
        let songs: [(String, Double)]
    }

    static let entries: [Entry] = [
        Entry(artist: "Charli xcx", title: "BRAT", genre: "Electronic", year: 2024, love: 1.0,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/88/4e/63/884e6321-ad41-aab1-f6f0-20efcafcfd55/075679666130.jpg/1400x1400bb.jpg",
              songs: [("360", 134), ("Club classics", 154), ("Sympathy is a knife", 151), ("I might say something stupid", 109), ("Talk talk", 162), ("Von dutch", 164), ("Everything is romantic", 203), ("Rewind", 168)]),
        Entry(artist: "Doja Cat", title: "Planet Her", genre: "Pop", year: 2021, love: 0.78,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/4f/4b/ee/4f4bee71-d197-67ab-2a42-913dc416df0d/886449138869.jpg/1400x1400bb.jpg",
              songs: [("Woman", 173), ("Naked", 224), ("Payday (feat. Young Thug)", 213), ("Get Into It (Yuh)", 138), ("Need To Know", 211), ("Love To Dream", 217), ("You Right", 186), ("Been Like This", 177)]),
        Entry(artist: "Yeat", title: "2093", genre: "Hip-Hop", year: 2024, love: 0.7,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/b1/69/86/b169862a-cdb8-6a0a-8359-03e86921f306/24UMGIM13668.rgb.jpg/1400x1400bb.jpg",
              songs: [("Psycho CEO", 226), ("Power Trip", 265), ("Breathe", 171), ("Morë", 165), ("Bought The Earth", 178), ("Nothing Changë", 237), ("U Should Know", 186), ("Lyfestylë", 237)]),
        Entry(artist: "Drake", title: "For All The Dogs", genre: "Hip-Hop", year: 2023, love: 0.42,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/fa/9e/e6/fa9ee672-0880-2b5b-a69d-981e8fcb807e/23UM1IM09863.rgb.jpg/1400x1400bb.jpg",
              songs: [("Virginia Beach", 251), ("Amen (feat. Teezo Touchdown)", 141), ("Calling For You (feat. 21 Savage)", 286), ("Fear Of Heights", 155), ("Daylight", 164), ("First Person Shooter (feat. J. Cole)", 247), ("IDGAF (feat. Yeat)", 260), ("7969 Santa", 260)]),
        Entry(artist: "Charli xcx", title: "CRASH", genre: "Pop", year: 2022, love: 0.72,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/86/08/4f/86084fe8-8613-74a6-846a-f6419e030c5c/190296409165.jpg/1400x1400bb.jpg",
              songs: [("Crash", 130), ("New Shapes (feat. Caroline Polachek & Christine and the Queens)", 201), ("Good Ones", 137), ("Constant Repeat", 189), ("Beg For You (feat. Rina Sawayama)", 168), ("Move Me", 147), ("Baby", 160), ("Lightning", 237)]),
        Entry(artist: "Doja Cat", title: "Scarlet", genre: "Rap", year: 2023, love: 0.45,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/21/61/09/216109c7-74f9-a99a-f2e9-0405d7ed2fea/196871470148.jpg/1400x1400bb.jpg",
              songs: [("Paint The Town Red", 230), ("Demons", 196), ("Ouchies", 122), ("97", 178), ("Gun", 177), ("Go Off", 197), ("Shutcho", 187), ("Agora Hills", 265)]),
        Entry(artist: "Drake", title: "Take Care", genre: "Hip-Hop", year: 2011, love: 0.66,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/d2/53/62/d2536245-b94c-b3fd-7168-9512f655f6d4/00602527899091.rgb.jpg/1400x1400bb.jpg",
              songs: [("Over My Dead Body", 273), ("Shot for Me", 225), ("Headlines", 236), ("Crew Love (feat. The Weeknd)", 209), ("Take Care (feat. Rihanna)", 277), ("Marvin's Room", 347), ("Buried Alive Interlude (feat. Kendrick Lamar)", 151), ("Under Ground Kings", 213)]),
        Entry(artist: "Yeat", title: "2 Alivë", genre: "Hip-Hop", year: 2022, love: 0.5,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/6c/13/d6/6c13d6fc-2993-020f-22a6-82c68cfe908c/22UMGIM22801.rgb.jpg/1400x1400bb.jpg",
              songs: [("Poppin", 167), ("Outsidë (feat. Young Thug)", 231), ("Rëal six", 209), ("Nvr again", 166), ("Luh gëek", 176), ("Rackz got më (feat. Gunna)", 181), ("Doublë", 170), ("On tha linë", 155)]),
        Entry(artist: "Charli xcx", title: "how i'm feeling now", genre: "Pop", year: 2020, love: 0.6,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/1a/5c/e9/1a5ce93c-aef4-6667-b7d1-7162203e1c39/190295229993.jpg/1400x1400bb.jpg",
              songs: [("pink diamond", 124), ("forever", 244), ("claws", 149), ("7 years", 195), ("detonate", 219), ("enemy", 223), ("i finally understand", 152), ("c2.0", 221)]),
        Entry(artist: "Drake", title: "Views", genre: "Hip-Hop", year: 2016, love: 0.5,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/95/f5/87/95f587f7-21c3-d5f9-d81a-4350f9caa020/16UMGIM27643.rgb.jpg/1400x1400bb.jpg",
              songs: [("Keep the Family Close", 329), ("9", 256), ("U With Me?", 297), ("Feel No Ways", 241), ("Hype", 209), ("Weston Road Flows", 254), ("Redemption", 334), ("With You (feat. PARTYNEXTDOOR)", 195)]),
        Entry(artist: "Doja Cat", title: "Hot Pink", genre: "R&B", year: 2019, love: 0.55,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/f3/03/40/f30340af-55d6-11bb-f59c-b03705360715/886447991831.jpg/1400x1400bb.jpg",
              songs: [("Won't Bite (feat. Smino)", 195), ("Rules", 187), ("Say So", 238), ("Like That (feat. Gucci Mane)", 163), ("Addiction", 208), ("Streets", 227), ("Shine", 160)]),
        Entry(artist: "Drake", title: "Scorpion", genre: "Hip-Hop", year: 2018, love: 0.46,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/bb/6d/8f/bb6d8f67-6d04-10b5-dd62-eb5809ac54fc/00602567879152.rgb.jpg/1400x1400bb.jpg",
              songs: [("Survival", 136), ("Nonstop", 239), ("Elevate", 185), ("Emotionless", 302), ("God's Plan", 199), ("I'm Upset", 214), ("8 Out Of 10", 196), ("Mob Ties", 205)]),
        Entry(artist: "Yeat", title: "AftërLyfe", genre: "Hip-Hop", year: 2023, love: 0.36,
              artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/6c/01/ba/6c01ba5c-ba17-6be7-bb8d-cf26054df5d6/23UMGIM16901.rgb.jpg/1400x1400bb.jpg",
              songs: [("No morë talk", 239), ("Shmunk (feat. YoungBoy Never Broke Again)", 230), ("Bëttr 0ff", 230), ("Rav3 p4rty (feat. Kranky Kranky)", 199), ("Nun id change", 211), ("Woa...!", 170), ("Now (feat. LUH GEEKY)", 272), ("Slamm", 145)]),
        // The song the demo plays is invented, with words written for LINER., so no one's lyrics are shown.
        Entry(artist: "Marlowe Vane", title: "Paper Moons", genre: "Indie Pop", year: 2025, love: 0.12,
              colours: [0xF2A65A, 0xE4572E, 0x2E1F47, 0xF7D488], style: .sun,
              songs: [("Paper Moons", 214), ("Kerosene Summer", 189), ("Night Bus Home", 201), ("Ribbons", 176)]),
    ]

    /// Album IDs start here; song IDs are album × 100 + track.
    static func albumID(_ index: Int) -> UInt64 { UInt64(7_000 + index) }

    /// The invented album the demo plays from (the last one).
    static var nowPlayingAlbum: UInt64 { albumID(entries.count - 1) }
    /// The song the demo plays: its first track.
    static var nowPlayingID: UInt64 { nowPlayingAlbum * 100 + 1 }

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
            for (t, (title, length)) in e.songs.enumerated() {
                let sid = id * 100 + UInt64(t + 1)
                ids.append(sid)
                // Openers and singles get played most; a little wobble so ranks look real.
                let base = 40 + e.love * 380
                let shape = t == 0 ? 1.0 : 0.45 + 0.5 / Double(t + 1)
                let wobble = Double((Int(sid) * 37) % 23) / 23.0 * 0.35 + 0.8
                let plays = Int(base * shape * wobble)
                songs.append(Song(id: sid, title: title, artist: e.artist, albumTitle: e.title, albumArtist: e.artist,
                                  albumID: id, genre: e.genre, composer: e.artist, duration: length,
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
