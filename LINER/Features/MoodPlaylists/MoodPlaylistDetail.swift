import SwiftData
import SwiftUI

/// A mood playlist: its songs, Play/Shuffle, refresh, weekly auto-refresh, and Save as Apple Music playlist.
struct MoodPlaylistDetail: View {
    @Bindable var playlist: MoodPlaylist
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var message: String?

    var body: some View {
        let songs = MoodPlaylistService.songs(playlist, library: library)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MoodCover(playlist: playlist, songs: songs).frame(maxWidth: 260).frame(maxWidth: .infinity)
                Text(playlist.name).font(.itemTitle)
                if !playlist.summary.isEmpty { Text(playlist.summary).font(.callout).foregroundStyle(Palette.secondary) }
                Text("Mood playlist · \(songs.count) songs · \(songs.reduce(0) { $0 + $1.duration }.minutesLabel)").linerLabel(size: 10)
                PlayShuffleRow(songs: songs)
                Toggle("Refresh every week", isOn: $playlist.autoRefresh).font(.subheadline)
                HStack {
                    Button(working ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise") {
                        Task { working = true; await MoodPlaylistService.refresh(playlist, library: library); working = false }
                    }
                    Spacer()
                    Button("Save to Apple Music", systemImage: "plus.square.on.square") {
                        Task { message = await MoodPlaylistService.saveToAppleMusic(playlist, library: library) }
                    }
                }
                .buttonStyle(.linerGlass).font(.footnote)
                if let message { Text(message).font(.footnote).foregroundStyle(Palette.secondary) }
                LazyVStack(spacing: 0) {
                    ForEach(songs) { s in PlayableSongRow(song: s, list: songs).padding(.vertical, 6) }
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Store.shared.context.delete(playlist)
                        Store.shared.save()
                        dismiss()
                    }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
    }
}

/// A 2×2 mosaic of the playlist's covers with a soft glass mood label.
struct MoodCover: View {
    let playlist: MoodPlaylist
    let songs: [Song]
    var body: some View {
        let ids = Array(Set(songs.map(\.albumID))).prefix(4).map { $0 }
        PlaylistCover(playlist: Playlist(id: 0, name: playlist.name, songIDs: [], coverAlbumIDs: ids, playCount: 0, dateAdded: nil))
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "sparkles").font(.caption).padding(8).glassEffect(.regular, in: .circle).padding(8)
            }
    }
}

/// Mood Playlists, opened from the sparkles button on Home: make a new one, or open one you've made.
struct MoodPlaylistsSheet: View {
    @Query(sort: \MoodPlaylist.createdAt, order: .reverse) private var playlists: [MoodPlaylist]
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var building = false
    @State private var made: MoodPlaylist?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { building = true } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New mood playlist").font(.system(size: 16, weight: .semibold))
                                Text(MoodAI.state == .available ? "Describe a vibe" : "Build a Mood Mix").font(.caption).foregroundStyle(Palette.secondary)
                            }
                        } icon: { Image(systemName: "sparkles") }
                    }
                }
                if !playlists.isEmpty {
                    Section("Your mood playlists") {
                        ForEach(playlists) { p in
                            NavigationLink(value: p) {
                                HStack(spacing: 12) {
                                    MoodCover(playlist: p, songs: MoodPlaylistService.songs(p, library: library)).frame(width: 52, height: 52)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.system(size: 16, weight: .medium)).lineLimit(1)
                                        Text("\(p.trackIDs.count) songs").font(.caption).foregroundStyle(Palette.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mood Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .navigationDestination(for: MoodPlaylist.self) { MoodPlaylistDetail(playlist: $0) }
            .navigationDestination(item: $made) { MoodPlaylistDetail(playlist: $0) }
            .sheet(isPresented: $building) { MoodBuilderSheet { made = $0 } }
        }
    }
}
