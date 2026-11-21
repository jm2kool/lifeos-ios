import SwiftUI

/// The numbers printed on a passport card, worked out from your library when the card is made.
struct PassportFacts {
    var number = 1
    var fields: [(String, String)] = []
    var rank: Int?
    var rankOf = 0
    var rankNoun = "songs"
    var plays: Int?
    var minutes: Int?
    var hearts: Int?

    @MainActor static func make(_ c: ShareContent, library: LibraryService) -> PassportFacts {
        let stats = library.stats, snap = library.snapshot
        var f = PassportFacts(hearts: c.hearts)
        if let song = c.coverItem?.song, c.kind == .song || c.kind == .nowPlaying {
            let i = stats.songs.firstIndex { $0.id == song.id }
            f.rank = i.map { $0 + 1 }
            f.rankOf = stats.songs.count
            f.plays = song.playCount
            f.minutes = Int(Double(song.playCount) * song.duration / 60)
            f.fields = [("Title", song.title), ("Artist", song.artist), ("Album", song.albumTitle)]
            let year = song.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
            let line = [year, song.genre.isEmpty ? nil : song.genre].compactMap { $0 }.joined(separator: " · ")
            if !line.isEmpty { f.fields.append(("Released · Genre", line)) }
        } else if c.kind == .album, let id = c.albumID, let album = snap.album(id) {
            f.rank = stats.rank(of: album)
            f.rankOf = stats.albums.count
            f.rankNoun = "albums"
            f.plays = album.playCount
            f.minutes = stats.minutes(of: album)
            f.fields = [("Album", album.title), ("Artist", album.artist), ("Songs", "\(album.songCount)")]
            let line = [album.year.map(String.init), album.genre.isEmpty ? nil : album.genre].compactMap { $0 }.joined(separator: " · ")
            if !line.isEmpty { f.fields.append(("Released · Genre", line)) }
        } else if c.kind == .artist, let name = c.portraitName, let artist = snap.artist(named: name) {
            f.rank = stats.rank(of: artist)
            f.rankOf = stats.artists.count
            f.rankNoun = "artists"
            f.plays = artist.playCount
            f.minutes = stats.minutes(of: artist)
            f.fields = [("Artist", artist.name), ("Releases", "\(artist.albumIDs.count)"), ("Songs", "\(artist.songCount)")]
        }
        f.number = f.rank ?? 1
        return f
    }
}

/// A 1080 × 1920 passport page: the cover, the facts, your rank, hearts and plays, a stamp, and the machine
/// readable lines along the bottom, on the cover's colour with faint guilloché waves.
struct PassportCard: View {
    let content: ShareContent
    let facts: PassportFacts
    let cover: UIImage?
    let look: ArtworkLook
    /// Covers for top-ten rows, by album.
    var rowCovers: [UInt64: UIImage] = [:]

    private var paper: Color { look.dominant.mix(with: .black, by: 0.62) }
    private var ink: Color { look.dominant.mix(with: .white, by: 0.72) }
    private var faint: Color { ink.opacity(0.55) }
    private var isList: Bool { !content.ranked.isEmpty }

    var body: some View {
        ZStack(alignment: .topLeading) {
            paper
            Waves().stroke(ink.opacity(0.06), lineWidth: 2)
            VStack(alignment: .leading, spacing: 0) {
                header
                rule.padding(.vertical, 44)
                if isList { list } else { single }
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 66)
            .padding(.top, 70)
            .padding(.bottom, 80)
        }
        .foregroundStyle(ink)
        .frame(width: 1080, height: 1920)
    }

    private var rule: some View { Rectangle().fill(ink.opacity(0.2)).frame(height: 2) }

    private var header: some View {
        HStack(alignment: .center) {
            Image("Logo").resizable().scaledToFill().frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(AppBrand.name).font(.system(size: 76, weight: .bold, design: .serif)).padding(.leading, 26)
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Text(content.kicker.uppercased()).font(.system(size: 28, weight: .semibold)).tracking(7).foregroundStyle(faint)
                Text(isList ? content.title.uppercased() : "NO. \(String(format: "%06d", facts.number))")
                    .font(.system(size: 38, weight: .medium, design: .monospaced))
            }
        }
    }

    private var single: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 44) {
                coverView(cover).frame(width: 400, height: 400)
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(Array(facts.fields.enumerated()), id: \.offset) { _, field in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(field.0.uppercased()).font(.system(size: 24, weight: .semibold)).tracking(6).foregroundStyle(faint)
                            Text(field.1).font(.system(size: 38, weight: .medium)).lineLimit(2).minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            rule.padding(.vertical, 50)
            Text("MY LIBRARY RANK").font(.system(size: 28, weight: .semibold)).tracking(7).foregroundStyle(faint)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(facts.rank.map { "#\($0)" } ?? "—").font(.system(size: 230, weight: .black, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if let rank = facts.rank, facts.rankOf > 0 {
                        Text("of \(facts.rankOf.grouped) \(facts.rankNoun) · Top \(topPercent(rank))")
                            .font(.system(size: 40, weight: .medium)).foregroundStyle(faint)
                    }
                }
                Spacer()
                if let h = facts.hearts, h > 0 {
                    VStack(alignment: .trailing, spacing: 14) {
                        Text("MY RATING").font(.system(size: 26, weight: .semibold)).tracking(6).foregroundStyle(faint)
                        HStack(spacing: 10) {
                            ForEach(0..<5, id: \.self) { i in Image(systemName: i < h ? "heart.fill" : "heart").font(.system(size: 48)) }
                        }
                    }
                }
            }
            HStack(alignment: .top) {
                statBlock("Total plays", facts.plays.map { $0.grouped })
                Spacer()
                statBlock("Listening time", facts.minutes.map { "\($0.grouped) min" })
                Spacer()
            }
            .padding(.top, 60)
            HStack {
                Spacer()
                stamp.padding(.top, 30)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 34) {
            if let first = content.ranked.first {
                HStack(alignment: .center, spacing: 44) {
                    coverView(first.albumID.flatMap { rowCovers[$0] } ?? cover).frame(width: 400, height: 400)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("#1").font(.system(size: 160, weight: .black, design: .rounded))
                        Text(first.title).font(.system(size: 52, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.6)
                        Text(first.subtitle).font(.system(size: 38)).foregroundStyle(faint).lineLimit(1)
                        Text("\(first.value) plays").font(.system(size: 36, design: .monospaced)).foregroundStyle(faint)
                    }
                }
                .padding(.bottom, 12)
            }
            ForEach(Array(content.ranked.dropFirst().enumerated()), id: \.offset) { i, row in
                HStack(spacing: 30) {
                    Text(String(format: "%02d", i + 2)).font(.system(size: 36, design: .monospaced)).foregroundStyle(faint).frame(width: 66, alignment: .leading)
                    coverView(row.albumID.flatMap { rowCovers[$0] }).frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.system(size: 38, weight: .semibold)).lineLimit(1)
                        Text(row.subtitle).font(.system(size: 30)).foregroundStyle(faint).lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    Text(row.value).font(.system(size: 34, design: .monospaced)).foregroundStyle(faint)
                }
            }
        }
    }

    private func coverView(_ image: UIImage?) -> some View {
        ZStack {
            ink.opacity(0.1)
            if let image { FillImage(image: image) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ink.opacity(0.15), lineWidth: 2))
    }

    private func statBlock(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label.uppercased()).font(.system(size: 26, weight: .semibold)).tracking(6).foregroundStyle(faint)
            Text(value ?? "—").font(.system(size: 56, weight: .medium))
        }
    }

    /// A round ink stamp: "LINER. 501× PLAYED".
    private var stamp: some View {
        ZStack {
            Circle().stroke(ink.opacity(0.55), lineWidth: 5)
            Circle().inset(by: 18).stroke(ink.opacity(0.4), lineWidth: 2)
            VStack(spacing: 6) {
                Text(AppBrand.name.uppercased()).font(.system(size: 30, weight: .bold)).tracking(6)
                Text("\(facts.plays ?? 0)×").font(.system(size: 64, weight: .heavy, design: .rounded))
                Text("PLAYED").font(.system(size: 30, weight: .bold)).tracking(8)
            }
            .foregroundStyle(ink.opacity(0.6))
        }
        .frame(width: 280, height: 280)
        .rotationEffect(.degrees(-14))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR MUSIC PASSPORT").font(.system(size: 26, weight: .semibold)).tracking(8).foregroundStyle(faint)
            ForEach(machineLines, id: \.self) { line in
                Text(line).font(.system(size: 38, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(ink.opacity(0.8))
            }
        }
    }

    /// The two machine-readable lines, padded with chevrons like a real passport.
    private var machineLines: [String] {
        func code(_ s: String) -> String {
            s.uppercased().folding(options: .diacriticInsensitive, locale: nil)
                .map { $0.isLetter || $0.isNumber ? String($0) : "<" }.joined()
        }
        func pad(_ s: String) -> String { String((s + String(repeating: "<", count: 44)).prefix(44)) }
        let brand = code(AppBrand.name.replacingOccurrences(of: ".", with: ""))
        if isList {
            return [pad("T<\(brand)<\(code(content.kicker))<<\(code(content.title))"),
                    pad("1<\(code(content.ranked.first?.title ?? ""))<<\(code(content.ranked.first?.value ?? ""))PLAYS")]
        }
        let first = facts.fields.first?.1 ?? content.title, second = facts.fields.dropFirst().first?.1 ?? content.subtitle
        return [pad("P<\(brand)<\(code(first))<<\(code(second))"),
                pad("\(String(format: "%06d", facts.number))<\(facts.plays ?? 0)PLAYS<<\(facts.minutes ?? 0)MIN")]
    }

    private func topPercent(_ rank: Int) -> String {
        let p = Double(rank) / Double(max(1, facts.rankOf)) * 100
        return p < 1 ? String(format: "%.1f%%", p) : "\(Int(p.rounded(.up)))%"
    }
}

/// Faint wavy lines across the page.
private struct Waves: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let rows = 14, amplitude = rect.height / CGFloat(rows) * 0.45
        for r in 0..<rows {
            let y0 = rect.height * CGFloat(r) / CGFloat(rows - 1)
            p.move(to: CGPoint(x: 0, y: y0))
            for x in stride(from: CGFloat(0), through: rect.width, by: 12) {
                let y = y0 + sin(x / rect.width * .pi * 3 + CGFloat(r) * 0.9) * amplitude
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return p
    }
}

#Preview {
    PassportCard(content: .top(.topAlbums, stats: PreviewData.library.stats), facts: PassportFacts(), cover: nil, look: .neutral)
        .scaleEffect(0.3).frame(width: 324, height: 576).preferredColorScheme(.dark)
}
