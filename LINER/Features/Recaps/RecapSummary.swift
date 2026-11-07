import SwiftUI

/// A recap in My LINER. → Recaps: minutes with the change, song of the period, top 5s, genre, moods, discoveries.
struct RecapSummary: View {
    let recap: Recap
    let namespace: Namespace.ID
    let playStory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Card {
                Text("Minutes listened").linerLabel(size: 10)
                HStack(alignment: .firstTextBaseline) {
                    CountUpText(value: recap.minutes, font: .serif(54))
                    if let c = recap.change {
                        Label("\(abs(c))%", systemImage: c >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(c >= 0 ? .green : .orange)
                    }
                }
                Text("\(recap.plays.grouped) plays · estimated from durations").font(.caption).foregroundStyle(Palette.label)
                GlassPillButton(title: "Play your story", systemImage: "play.rectangle.on.rectangle", prominent: true, action: playStory)
            }
            .padding(.horizontal, 16)

            if let song = recap.song {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Song of the \(recap.period.kind.rawValue)").font(.sectionTitle)
                    HStack(spacing: 14) {
                        ArtworkView(albumID: song.albumID, cornerRadius: 14).frame(width: 110, height: 110)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.name).font(.serif(24)).lineLimit(2)
                            Text(song.detail).linerLabel(size: 10)
                            Text("\(Int(song.plays.rounded())) plays").font(.caption).foregroundStyle(Palette.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            ranked("Top Artists", recap.topArtists)
            ranked("Top Albums", recap.topAlbums)
            ranked("Top Songs", recap.topSongs)

            StatRow {
                StatTile("Top genre", text: recap.topGenre ?? "—")
                StatTile("New discoveries", value: recap.discoveries.count)
            }
            .padding(.horizontal, 16)
            if !recap.topMoods.isEmpty {
                Card {
                    Text("Top moods").linerLabel(size: 10)
                    Text(recap.topMoods.joined(separator: " · ")).font(.serif(22))
                }
                .padding(.horizontal, 16)
            }
            if let day = recap.busiestDay {
                Card {
                    Text("Most-replayed day").linerLabel(size: 10)
                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month())).font(.serif(22))
                    Text("\(day.plays) plays").font(.caption).foregroundStyle(Palette.secondary)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder private func ranked(_ title: String, _ list: [Recap.Ranked]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.sectionTitle)
                ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.serif(18)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 24)
                        if r.albumID != nil || title != "Top Artists" {
                            ArtworkView(albumID: r.albumID, cornerRadius: 6).frame(width: 40, height: 40)
                        } else {
                            ArtistPortraitView(name: r.name).frame(width: 40, height: 40).clipShape(Circle())
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).lineLimit(1)
                            if !r.detail.isEmpty { Text(r.detail).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Text("\(Int(r.plays.rounded()))").font(.serif(16)).monospacedDigit().foregroundStyle(Palette.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// A number that counts up from zero when it appears.
struct CountUpText: View {
    let value: Int
    var font: Font = .statNumber
    @State private var shown = 0

    var body: some View {
        Text(shown.grouped).font(font).monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear { animate() }
            .onChange(of: value) { animate() }
            .accessibilityLabel(value.grouped)
    }

    private func animate() {
        shown = 0
        withAnimation(.easeOut(duration: 1.2)) { shown = value }
    }
}
