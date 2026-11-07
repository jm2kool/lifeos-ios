import Foundation

/// Editing what plays next. Only upcoming items move; the current one stays put.
extension PlaybackCoordinator {
    func playNext(_ items: [QueueItem]) {
        guard current != nil else { play(items); return }
        editQueue { q, i in q.insert(contentsOf: items, at: i + 1) }
    }

    func addToQueue(_ items: [QueueItem]) {
        guard current != nil else { play(items); return }
        editQueue { q, _ in q.append(contentsOf: items) }
    }

    /// Moves within Up Next (offsets are relative to `upNext`).
    func moveUpNext(from source: IndexSet, to destination: Int) {
        editQueue { q, i in
            var upcoming = Array(q[(i + 1)...])
            upcoming.move(fromOffsets: source, toOffset: destination)
            q.replaceSubrange((i + 1)..., with: upcoming)
        }
    }

    func removeUpNext(at offsets: IndexSet) {
        editQueue { q, i in
            var upcoming = Array(q[(i + 1)...])
            upcoming.remove(atOffsets: offsets)
            q.replaceSubrange((i + 1)..., with: upcoming)
        }
    }
}
