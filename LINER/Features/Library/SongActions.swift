import SwiftUI

/// Long-press actions for a song: play next, add to queue, go to album.
struct SongContextMenu: ViewModifier {
    let song: Song
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(LibraryService.self) private var library
    @Environment(PassportPresenter.self) private var passports

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Song Passport", systemImage: "text.book.closed") { passports.song = .library(song) }
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext([.library(song)]) }
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue([.library(song)]) }
            if let album = library.snapshot.album(song.albumID) {
                NavigationLink(value: album) { Label("Go to Album", systemImage: "square.stack") }
            }
            if let artist = library.snapshot.artist(named: song.albumArtist) {
                NavigationLink(value: artist) { Label("Go to Artist", systemImage: "person") }
            }
        }
    }
}

/// A song row that plays the list from this song when tapped.
struct PlayableSongRow: View {
    let song: Song
    let list: [Song]
    var number: Int?
    var showArtwork = true
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        Button {
            // Keep queues to a sensible size: this song and what follows it.
            let start = list.firstIndex(of: song) ?? 0
            let slice = Array(list[start..<min(list.count, start + 300)])
            player.play(songs: slice)
        } label: {
            SongRow(song: song, number: number, showArtwork: showArtwork)
                .overlay(alignment: .leading) {
                    if player.current?.libraryID == song.id {
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .font(.caption).offset(x: number == nil ? -14 : -10)
                    }
                }
        }
        .buttonStyle(.plain)
        .modifier(SongContextMenu(song: song))
    }
}

/// Glass Play and Shuffle buttons for any list of songs.
struct PlayShuffleRow: View {
    let songs: [Song]
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        PlayShuffleIcons(play: { player.play(songs: songs) }, shuffle: { player.play(songs: songs, shuffled: true) })
            .disabled(songs.isEmpty)
    }
}
