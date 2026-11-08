import SwiftUI

/// Where an album opens. In Vinyl Mode it opens as a gatefold sleeve; otherwise it's the album page with every
/// song. Nothing plays until you ask ("Put it on" is the way onto the turntable).
struct AlbumDestination: View {
    let album: Album
    @AppStorage("vinylMode") private var vinylMode = false
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if vinylMode {
            GatefoldView(record: .album(album, library.snapshot)) { dismiss() }
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        } else {
            AlbumDetailView(album: album)
        }
    }
}

#Preview {
    NavigationStack { AlbumDestination(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
