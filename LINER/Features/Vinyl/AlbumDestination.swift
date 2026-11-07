import SwiftUI

/// Where an album opens: always the album page with every song, Vinyl Mode or not. Nothing plays until you ask
/// (the crate's "Put it on" is the way onto the turntable).
struct AlbumDestination: View {
    let album: Album

    var body: some View { AlbumDetailView(album: album) }
}

#Preview {
    NavigationStack { AlbumDestination(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
