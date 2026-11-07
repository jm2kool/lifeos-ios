import SwiftData
import SwiftUI

/// My Stats sections built from your passports: most-loved albums and most-used moods.
struct PersonalStatsSections: View {
    @Query(filter: #Predicate<AlbumNote> { $0.rating != nil }) private var ratedAlbums: [AlbumNote]
    @Query private var songNotes: [SongNote]
    @Environment(LibraryService.self) private var library

    var body: some View {
        let loved = ratedAlbums.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.compactMap { note -> (Album, Int)? in
            guard note.albumID.hasPrefix("album-"), let id = UInt64(note.albumID.dropFirst(6)),
                  let album = library.snapshot.album(id) else { return nil }
            return (album, note.rating ?? 0)
        }
        var counts: [String: Int] = [:]
        for n in songNotes { for m in n.moods { counts[m, default: 0] += 1 } }
        let moods = counts.sorted { $0.value > $1.value }.prefix(8)

        return VStack(alignment: .leading, spacing: 26) {
            if !loved.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most Loved Albums").font(.sectionTitle).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(loved, id: \.0.id) { album, hearts in
                                NavigationLink(value: album) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        AlbumTile(album: album).frame(width: 140)
                                        Text(String(repeating: "♥", count: hearts)).font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            if !moods.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Most-Used Moods").font(.sectionTitle)
                    ForEach(Array(moods), id: \.key) { mood, n in
                        HStack {
                            Text(mood).font(.serif(18))
                            Spacer()
                            Text("\(n) song\(n == 1 ? "" : "s")").linerLabel(size: 10)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
