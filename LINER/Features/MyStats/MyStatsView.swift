import SwiftUI

/// "My LINER." — all-time numbers from your library. Rankings and See All lists come in Phase 3.
struct MyStatsView: View {
    @Environment(LibraryService.self) private var library

    var body: some View {
        let snap = library.snapshot
        let plays = snap.songs.reduce(0) { $0 + $1.playCount }
        let minutes = Int(snap.songs.reduce(0) { $0 + Double($1.playCount) * $1.duration } / 60)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My \(AppBrand.name)").font(.serif(44))
                        Text(AppBrand.tagline).linerLabel()
                    }
                    HStack(spacing: 12) {
                        StatTile("Total plays", value: plays)
                        StatTile("Minutes", value: minutes, footnote: "Estimated")
                    }
                    HStack(spacing: 12) {
                        StatTile("Songs", value: snap.songs.count)
                        StatTile("Albums", value: snap.albums.count)
                        StatTile("Artists", value: snap.artists.count)
                    }
                    Text("Minutes are estimated from track durations × play counts.")
                        .font(.footnote).foregroundStyle(Palette.label)
                }
                .padding(16)
            }
            .background(Palette.background)
            .refreshable { await library.refresh() }
        }
    }
}

#Preview { MyStatsView().environment(PreviewData.library).preferredColorScheme(.dark) }
