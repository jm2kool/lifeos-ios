import SwiftUI

/// The sleeve's own controls, so everything the album page offers is here too: the passport, "Put it on",
/// shuffle, and the ••• menu (play next, pin, cover, editions, download).
struct GatefoldControls: View {
    let record: VinylRecord
    let onPutOn: () -> Void
    let onShuffle: () -> Void
    @Environment(PassportPresenter.self) private var passports
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            GlassCircleButton(systemImage: "text.book.closed", label: "Passport", size: 44) { openPassport() }
            Menu {
                Button("Put it on", systemImage: "play.fill", action: onPutOn)
                Button("Shuffle", systemImage: "shuffle", action: onShuffle)
                Divider()
                if case .album(let album) = record.source {
                    AlbumActionsMenu(album: album)
                    Button("Download in Music", systemImage: "arrow.down.circle") { openInMusic(album) }
                } else {
                    Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext(record.tracks) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("More")
        }
    }

    private func openPassport() {
        switch record.source {
        case .album(let album): passports.album = .library(album, snapshot: library.snapshot)
        case .mixtape(let mixtape): passports.album = .mixtape(mixtape)
        default: break
        }
    }

    /// A third-party app can't download, so this opens the album in the Music app to download there.
    private func openInMusic(_ album: Album) {
        let songs = library.snapshot.songs(album.songIDs)
        if let id = songs.first(where: { !$0.storeID.isEmpty && $0.storeID != "0" })?.storeID,
           let url = URL(string: "https://music.apple.com/song/\(id)") {
            openURL(url)
        } else if let url = URL(string: "music://") {
            openURL(url)
        }
    }
}
