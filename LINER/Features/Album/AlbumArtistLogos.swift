import SwiftUI

/// The foot of an album page: the logos of the artists on it, like the credits on the back of a sleeve. The
/// album's own artists always show (as lettering when they have no logo); featured artists show when they have
/// a logo. Tap one you have in your library to open their page.
struct AlbumArtistLogos: View {
    let album: Album
    let songs: [Song]
    @Environment(LibraryService.self) private var library

    /// The album's artists first, then anyone else credited on its songs.
    private var names: (main: [String], featured: [String]) {
        let main = ArtistLogoStore.collaborators(album.artist).filter { MediaKey.normalise($0) != "variousartists" }
        var seen = Set(main.map(MediaKey.normalise) + [MediaKey.normalise(album.artist)])
        var featured: [String] = []
        for s in songs {
            for name in ArtistLogoStore.collaborators(s.artist) where seen.insert(MediaKey.normalise(name)).inserted {
                featured.append(name)
            }
        }
        return (main, Array(featured.prefix(4)))
    }

    var body: some View {
        let credits = names
        VStack(spacing: 18) {
            Rectangle().fill(Palette.stroke).frame(height: 1)
            ForEach(credits.main, id: \.self) { name in
                linked(name) {
                    ArtistTitleView(name: name, artistID: MediaKey.normalise(name), genre: album.genre, size: 26,
                                    style: ArtistTitleStyle.saved(for: MediaKey.normalise(name)))
                }
            }
            if !credits.featured.isEmpty {
                HStack(spacing: 24) {
                    ForEach(credits.featured, id: \.self) { name in linked(name) { FeaturedLogo(name: name) } }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func linked<V: View>(_ name: String, @ViewBuilder _ label: () -> V) -> some View {
        if let artist = library.snapshot.artist(named: name) {
            NavigationLink(value: artist) { label() }.buttonStyle(.plain)
        } else {
            label()
        }
    }
}

/// A featured artist's logo, small and white; nothing at all when they don't have one.
private struct FeaturedLogo: View {
    let name: String
    @State private var logo: UIImage?

    var body: some View {
        Group {
            if let logo {
                Image(uiImage: logo).renderingMode(.template).resizable().scaledToFit()
                    .frame(maxWidth: 120, maxHeight: 30)
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityLabel(name)
            }
        }
        .task(id: name) {
            if let hit = ArtistLogoStore.shared.cached(name) { logo = hit; return }
            guard !ArtistLogoStore.shared.knownMissing(name) else { return }
            logo = await ArtistLogoStore.shared.logo(for: name)
        }
    }
}

#Preview {
    AlbumArtistLogos(album: PreviewData.snapshot.albums[0], songs: PreviewData.snapshot.songs(PreviewData.snapshot.albums[0].songIDs))
        .padding().background(.black).environment(PreviewData.library).preferredColorScheme(.dark)
}
