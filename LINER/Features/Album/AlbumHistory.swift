import SwiftUI

/// My Listening History and Your Top 3 Songs.
struct AlbumHistory: View {
    let album: Album
    let songs: [Song]
    @Environment(LibraryService.self) private var library

    var body: some View {
        let top = songs.sorted { $0.playCount > $1.playCount }.prefix(3).filter { $0.playCount > 0 }
        VStack(alignment: .leading, spacing: 14) {
            Text("My Listening History").font(.sectionTitle)
            StatRow {
                StatTile("Avg plays", text: LibraryStats.averagePlays(album).formatted(.number.precision(.fractionLength(0...1))))
                StatTile("Minutes", value: library.stats.minutes(of: album), footnote: "Estimated")
                StatTile("Rank", text: library.stats.rank(of: album).map { "#\($0)" } ?? "—", footnote: "Top albums")
            }
            if !top.isEmpty {
                Text("Your Top 3 Songs").font(.sectionTitle).padding(.top, 8)
                ForEach(Array(top.enumerated()), id: \.element.id) { i, s in
                    PlayableSongRow(song: s, list: Array(top), number: i + 1).padding(.vertical, 4)
                }
            }
        }
    }
}

