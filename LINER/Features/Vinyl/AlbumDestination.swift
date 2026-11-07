import SwiftUI

/// Where an album opens: with Vinyl Mode on, straight onto the turntable (the ⓘ button shows the album page);
/// otherwise the album page.
struct AlbumDestination: View {
    let album: Album
    @AppStorage("vinylMode") private var vinylMode = false
    @Environment(LibraryService.self) private var library
    @State private var showDetails = false

    var body: some View {
        if vinylMode && !showDetails {
            TurntableView(record: .album(album, library.snapshot), onInfo: { withAnimation(.liner) { showDetails = true } })
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        } else {
            AlbumDetailView(album: album)
        }
    }
}
