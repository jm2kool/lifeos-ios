import SwiftUI

/// What a share card shows (SPEC §6.13): Song Passport, Album Passport, artist history, recap, now playing, lyric line.
struct ShareContent: Sendable {
    enum Kind: String, Sendable { case song, album, artist, recap, nowPlaying, lyric }

    var kind: Kind
    var kicker: String
    var title: String
    var subtitle: String
    var lines: [String] = []
    var stat: (label: String, value: String)?
    var hearts: Int?
    var quote: String?
    /// Which cover to put behind it.
    var coverItem: QueueItem?
    var albumID: UInt64?
    var portraitName: String?
    /// For the lock-screen style video background (album or mixtape artwork key).
    var artworkKey: String?

    static func nowPlaying(_ item: QueueItem) -> ShareContent {
        ShareContent(kind: .nowPlaying, kicker: "Now playing", title: item.title, subtitle: item.artist, lines: [item.albumTitle],
                     coverItem: item, artworkKey: item.artworkKey)
    }

    static func song(_ item: QueueItem, note: SongNote?, plays: Int?) -> ShareContent {
        var lines: [String] = []
        if let moods = note?.moods, !moods.isEmpty { lines.append(moods.prefix(4).joined(separator: " · ")) }
        if let n = note?.notes, !n.isEmpty { lines.append(String(n.prefix(160))) }
        return ShareContent(kind: .song, kicker: "Song Passport", title: item.title, subtitle: item.artist, lines: lines,
                            stat: plays.map { ("Plays", $0.grouped) }, hearts: note?.rating, quote: note?.lyricLines.first,
                            coverItem: item, artworkKey: item.artworkKey)
    }

    static func album(_ subject: AlbumSubject, rating: Int?, ranking: [QueueItem]) -> ShareContent {
        let top = ranking.prefix(3).enumerated().map { "\($0.offset + 1). \($0.element.title)" }
        return ShareContent(kind: .album, kicker: "Album Passport", title: subject.title, subtitle: subject.artist, lines: top,
                            stat: subject.album.map { ("Plays", $0.playCount.grouped) }, hearts: rating,
                            coverItem: subject.tracks.first, albumID: subject.album?.id, artworkKey: subject.id)
    }

    static func artist(_ a: Artist, rank: Int?, minutes: Int, topSong: Song?) -> ShareContent {
        var lines = ["\(a.playCount.grouped) plays · \(minutes.grouped) minutes"]
        if let s = topSong { lines.append("Most played: \(s.title)") }
        return ShareContent(kind: .artist, kicker: "My history", title: a.name, subtitle: rank.map { "#\($0) most played artist" } ?? "Artist",
                            lines: lines, albumID: a.albumIDs.first, portraitName: a.name, artworkKey: a.albumIDs.first.map { "album-\($0)" })
    }

    static func lyric(_ item: QueueItem, line: String) -> ShareContent {
        ShareContent(kind: .lyric, kicker: "Lyric", title: item.title, subtitle: item.artist, quote: line, coverItem: item, artworkKey: item.artworkKey)
    }

    static func recap(_ r: Recap, card: RecapStoryView.Card) -> ShareContent {
        let period = r.period.kind == .week ? "My week in music" : (r.period.kind == .month ? "My month in music" : "My year in music")
        var c = ShareContent(kind: .recap, kicker: period, title: r.period.title, subtitle: "\(r.minutes.grouped) minutes · \(r.plays.grouped) plays",
                             albumID: r.song?.albumID, artworkKey: r.song?.albumID.map { "album-\($0)" })
        switch card {
        case .artists: c.lines = r.topArtists.enumerated().map { "\($0.offset + 1). \($0.element.name)" }
        case .albums: c.lines = r.topAlbums.enumerated().map { "\($0.offset + 1). \($0.element.name)" }
        case .songs, .song: c.lines = r.topSongs.enumerated().map { "\($0.offset + 1). \($0.element.name) — \($0.element.detail)" }
        case .vibe: c.lines = [r.topGenre ?? "", r.topMoods.joined(separator: " · ")].filter { !$0.isEmpty }
        case .discoveries: c.lines = ["\(r.discoveries.count) new discoveries"] + r.discoveries.prefix(3).map(\.name)
        default: c.lines = r.song.map { ["Song of the \(r.period.kind.rawValue.lowercased()): \($0.name)"] } ?? []
        }
        return c
    }
}

/// The 1080 × 1920 overlay: words and numbers on a clear background (the cover or video goes underneath).
struct ShareOverlay: View {
    let content: ShareContent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.2),
                                   .init(color: .clear, location: 0.45), .init(color: .black.opacity(0.88), location: 0.78),
                                   .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 26) {
                Text(content.kicker.uppercased()).font(.system(size: 30, weight: .semibold)).tracking(8).foregroundStyle(.white.opacity(0.7))
                if let quote = content.quote, content.kind == .lyric {
                    Text("“\(quote)”").font(.system(size: 76, weight: .regular, design: .serif)).lineLimit(6).minimumScaleFactor(0.5)
                }
                Text(content.title).font(.system(size: content.kind == .lyric ? 54 : 104, weight: .regular, design: .serif))
                    .lineLimit(3).minimumScaleFactor(0.45)
                Text(content.subtitle.uppercased()).font(.system(size: 30, weight: .semibold)).tracking(6).foregroundStyle(.white.opacity(0.8))
                if let h = content.hearts, h > 0 {
                    Text(String(repeating: "♥", count: h) + String(repeating: "♡", count: 5 - h)).font(.system(size: 54)).foregroundStyle(.white)
                }
                ForEach(content.lines, id: \.self) { line in
                    Text(line).font(.system(size: 40, design: .serif)).foregroundStyle(.white.opacity(0.88)).lineLimit(3)
                }
                if let q = content.quote, content.kind != .lyric {
                    Text("“\(q)”").font(.system(size: 42, design: .serif)).italic().foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                }
                if let stat = content.stat {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(stat.value).font(.system(size: 92, design: .serif))
                        Text(stat.label.uppercased()).font(.system(size: 28, weight: .semibold)).tracking(6).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Text(AppBrand.name).font(.system(size: 40, design: .serif)).foregroundStyle(.white.opacity(0.75)).padding(.top, 20)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 90)
            .padding(.bottom, 170)
        }
        .frame(width: 1080, height: 1920)
    }
}

/// The still background: the cover filling 9:16 (or the artist's B&W portrait).
struct ShareBackground: View {
    let image: UIImage?
    var body: some View {
        ZStack {
            Color.black
            if let image { FocusedFillImage(image: image).frame(width: 1080, height: 1920) }
        }
        .frame(width: 1080, height: 1920)
        .clipped()
    }
}
