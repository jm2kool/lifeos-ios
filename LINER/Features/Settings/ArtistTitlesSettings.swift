import SwiftUI

/// Settings → Artist titles: pick how each artist's name is drawn on their page (their logo, or a lettering
/// style), instead of a menu on every artist page.
struct ArtistTitlesSettings: View {
    @Environment(LibraryService.self) private var library
    @State private var query = ""

    var body: some View {
        let artists = library.artists(.mostPlayed).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        List {
            Section {
                ForEach(artists) { ArtistTitleRow(artist: $0) }
            } footer: {
                Text("Automatic uses the artist's logo when there is one, and otherwise lettering that suits their music.")
            }
        }
        .searchable(text: $query, prompt: "Search artists")
        .navigationTitle("Artist titles")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One artist: a small preview of their title and the style picker.
private struct ArtistTitleRow: View {
    let artist: Artist
    @Environment(LibraryService.self) private var library
    @State private var style: ArtistTitleStyle = .auto

    var body: some View {
        let genre = library.snapshot.albums(of: artist).first?.genre ?? ""
        VStack(alignment: .leading, spacing: 8) {
            ArtistTitleView(name: artist.name, artistID: artist.id, genre: genre, size: 24, style: style).id(style)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Picker("Style", selection: $style) {
                ForEach(ArtistTitleStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(white: 0.08))
        .onAppear { style = ArtistTitleStyle.saved(for: artist.id) }
        .onChange(of: style) { _, s in ArtistTitleStyle.save(s, for: artist.id) }
    }
}

#Preview { NavigationStack { ArtistTitlesSettings() }.environment(PreviewData.library).preferredColorScheme(.dark) }
