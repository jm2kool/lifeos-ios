import Foundation

/// Connects the services: snapshots after each scan, the play log after each play, and a rescan shortly after
/// playback so the Music app's new play counts are picked up.
@MainActor
enum AppWiring {
    private static var rescan: Task<Void, Never>?

    static func connect(library: LibraryService, player: PlaybackCoordinator) {
        library.onRefresh = { [library] snapshot in
            Store.shared.rematch(with: snapshot)
            library.reloadPersonalRatings()
            SnapshotService.shared.record(snapshot)
        }
        player.onFinished = { [library] record in
            SnapshotService.shared.log(record)
            guard record.item.isLibrary else { return }
            rescan?.cancel()
            rescan = Task {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                await library.refresh()
            }
        }
    }
}
