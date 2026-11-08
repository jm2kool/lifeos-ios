import Foundation

/// Connects the services: snapshots after each scan, the play log after each play, and a rescan shortly after
/// playback so the Music app's new play counts are picked up.
@MainActor
enum AppWiring {
    private static var rescan: Task<Void, Never>?

    private static var refreshedMoods = false

    static func connect(library: LibraryService, player: PlaybackCoordinator) {
        library.onRefresh = { [library] snapshot in
            Store.shared.rematch(with: snapshot)
            Store.shared.adoptAlbumEditions(snapshot.albumAliases)
            library.reloadPersonalRatings()
            SnapshotService.shared.record(snapshot)
            NewAlbumPrompts.shared.check(snapshot)
            if !refreshedMoods {
                refreshedMoods = true
                Task { await MoodPlaylistService.refreshDue(library: library) }
            }
        }
        LiveLyricsLog.startObserving()
        player.onStarted = { item in LyricsLiveActivityController.shared.itemStarted(item) }
        player.onFinished = { [library] record in
            // Apple Music songs played from an artist page aren't in the library: nothing to count yet.
            guard record.item.song?.isCatalog != true else { return }
            SnapshotService.shared.log(record)
            guard record.item.isLibrary else { return }
            if record.viaOwnPlayer && record.completed {
                // Our own player's plays aren't in the Music app's counts: rescan to fold them into the stats.
                Task { await library.refresh() }
                return
            }
            rescan?.cancel()
            rescan = Task {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                await library.refresh()
            }
        }
    }
}
