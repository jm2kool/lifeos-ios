import SwiftData
import SwiftUI

/// The edition a queue was started from (an album page showing one of your editions). Its songs show the
/// edition's cover — in the player, the mini player and on the Lock Screen — even ones from other albums.
struct EditionCover: Equatable, Sendable {
    let editionID: UUID
    let itemIDs: Set<String>
}

extension EnvironmentValues {
    /// Set by an album page showing an edition, so its Play, Shuffle and song rows start the queue with it.
    @Entry var editionCover: EditionCover? = nil
}

extension CoverArt {
    /// The edition whose cover this item should wear: the edition its queue was started from, or otherwise its
    /// album's active edition. Nil when that edition has no cover or motion cover of its own.
    static func edition(for item: QueueItem) -> Edition? {
        if let context = PlaybackCoordinator.shared?.editionCover, context.itemIDs.contains(item.id),
           let e = Store.shared.edition(context.editionID), e.coverImage != nil || e.motionCoverFile != nil {
            return e
        }
        guard case .library(let song) = item, let note = Store.shared.albumNote("album-\(song.albumID)"),
              let id = note.activeEditionID, let e = Store.shared.edition(id), e.coverImage != nil || e.motionCoverFile != nil
        else { return nil }
        return e
    }

    /// The item's cover key, changed by an edition cover, for caches that must show the edition's cover.
    static func key(for item: QueueItem) -> String {
        guard let e = edition(for: item), let data = e.coverImage else { return item.coverKey }
        return item.coverKey + "-edition-\(e.id.uuidString.prefix(8))-\(data.count)"
    }

    /// Whether the item wears a cover of yours (an edition's or your own album cover) that the system's Now
    /// Playing wouldn't know about.
    static func hasOwnCover(_ item: QueueItem) -> Bool {
        if edition(for: item)?.coverImage != nil { return true }
        if case .library(let s) = item { return CoverOverrides.shared.image(s.albumID) != nil }
        return false
    }
}

extension Store {
    func edition(_ id: UUID) -> Edition? {
        var d = FetchDescriptor<Edition>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
