import SwiftUI

/// Story mode (SPEC §6.12): about eight full-screen cards, tap to go on, each over the song of the period's
/// Living Cover, with serif numbers that count up. Every card can be shared.
struct RecapStoryView: View {
    let recap: Recap
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var cover: UIImage?
    @State private var look = ArtworkLook.neutral
    @State private var started = Date.now

    enum Card: Hashable { case intro, minutes, song, artists, albums, songs, vibe, discoveries, outro }

    private var cards: [Card] {
        var c: [Card] = [.intro, .minutes]
        if recap.song != nil { c.append(.song) }
        if !recap.topArtists.isEmpty { c.append(.artists) }
        if !recap.topAlbums.isEmpty { c.append(.albums) }
        if !recap.topSongs.isEmpty { c.append(.songs) }
        if recap.topGenre != nil || !recap.topMoods.isEmpty { c.append(.vibe) }
        c.append(.discoveries)
        c.append(.outro)
        return c
    }

    var body: some View {
        let list = cards
        ZStack {
            Color.black
            if let cover { LivingCoverView(image: cover, look: look, key: "story-\(recap.period.id)").opacity(0.75) }
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            RecapCardContent(card: list[min(index, list.count - 1)], recap: recap)
                .id(index)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .padding(28)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { progress(list.count).padding(.top, 60).padding(.horizontal, 16) }
        .overlay(alignment: .topTrailing) {
            GlassCircleButton(systemImage: "xmark", label: "Close", size: 40) { dismiss() }.padding(.top, 76).padding(.trailing, 16)
        }
        .overlay(alignment: .bottom) {
            RecapShareButton(card: list[min(index, list.count - 1)], recap: recap, cover: cover).padding(.bottom, 44)
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let width = UIScreen.main.bounds.width
            withAnimation(.liner) {
                if location.x < width * 0.3 { index = max(0, index - 1) } else if index < list.count - 1 { index += 1 } else { dismiss() }
            }
            started = .now
        }
        .task {
            if let id = recap.song?.albumID, let img = await ArtworkCache.shared.image(album: id, pixels: 1600) {
                cover = img
                look = await ArtworkAnalysis.look(for: img, key: "album-\(id)")
            }
        }
        .statusBarHidden()
    }

    private func progress(_ count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= index ? Color.white : Color.white.opacity(0.3)).frame(height: 3)
            }
        }
        .padding(.trailing, 56)
    }
}

/// The words and numbers on one story card.
struct RecapCardContent: View {
    let card: RecapStoryView.Card
    let recap: Recap

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            switch card {
            case .intro:
                Text("Your \(recap.period.kind.rawValue.lowercased()) in music").linerLabel(size: 12)
                Text(recap.period.title).font(.serif(52))
                Text(AppBrand.name).font(.serif(22)).foregroundStyle(Palette.secondary)
            case .minutes:
                Text("You listened for").linerLabel(size: 12)
                CountUpText(value: recap.minutes, font: .serif(84))
                Text("minutes").font(.serif(30))
                if let c = recap.change {
                    Text("\(c >= 0 ? "↑" : "↓") \(abs(c))% on the \(recap.period.kind.rawValue.lowercased()) before").font(.serif(22)).foregroundStyle(Palette.secondary)
                }
            case .song:
                if let s = recap.song {
                    Text("Song of the \(recap.period.kind.rawValue.lowercased())").linerLabel(size: 12)
                    ArtworkView(albumID: s.albumID, cornerRadius: 18).frame(width: 220, height: 220)
                    Text(s.name).font(.serif(42)).lineLimit(3)
                    Text(s.detail).linerLabel(size: 12)
                    HStack(alignment: .firstTextBaseline, spacing: 8) { CountUpText(value: Int(s.plays.rounded()), font: .serif(40)); Text("plays").font(.serif(22)) }
                }
            case .artists: list("Top artists", recap.topArtists)
            case .albums: list("Top albums", recap.topAlbums)
            case .songs: list("Top songs", recap.topSongs)
            case .vibe:
                if let g = recap.topGenre {
                    Text("Your sound").linerLabel(size: 12)
                    Text(g).font(.serif(56))
                }
                if !recap.topMoods.isEmpty {
                    Text("Moods").linerLabel(size: 12).padding(.top, 12)
                    Text(recap.topMoods.joined(separator: "\n")).font(.serif(34))
                }
            case .discoveries:
                Text("New discoveries").linerLabel(size: 12)
                CountUpText(value: recap.discoveries.count, font: .serif(84))
                ForEach(recap.discoveries.prefix(3)) { d in Text("\(d.name) — \(d.detail)").font(.serif(20)).lineLimit(1) }
                if let day = recap.busiestDay {
                    Text("Most-replayed day: \(day.date.formatted(.dateTime.weekday(.wide))) (\(day.plays) plays)").font(.footnote).foregroundStyle(Palette.secondary).padding(.top, 8)
                }
            case .outro:
                Text("That was your \(recap.period.kind.rawValue.lowercased()).").font(.serif(44))
                Text("\(recap.plays.grouped) plays · \(recap.minutes.grouped) minutes").linerLabel(size: 12)
                Text("Made with \(AppBrand.name)").font(.serif(20)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ title: String, _ items: [Recap.Ranked]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).linerLabel(size: 12)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(i + 1)").font(.serif(30)).monospacedDigit().foregroundStyle(Palette.secondary).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.serif(i == 0 ? 32 : 24)).lineLimit(1)
                        if !r.detail.isEmpty { Text(r.detail).linerLabel(size: 10) }
                    }
                }
            }
        }
    }
}

/// Share a story card (filled in with share cards).
struct RecapShareButton: View {
    let card: RecapStoryView.Card
    let recap: Recap
    let cover: UIImage?
    var body: some View { ShareCardLauncher.recap(card: card, recap: recap, cover: cover) }
}
