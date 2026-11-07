import SwiftUI

/// A version number per album that changes whenever you set or clear your own cover, so every cache keyed on
/// the cover (colours, Living Covers, lock screen artwork) picks up the new one. Thread-safe.
enum CoverVersions {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var versions: [String: Int] =
        (UserDefaults.standard.dictionary(forKey: "coverVersions") as? [String: Int]) ?? [:]

    static func suffix(_ albumID: UInt64) -> String {
        let v = lock.withLock { versions[String(albumID)] ?? 0 }
        return v == 0 ? "" : "-v\(v)"
    }

    static func bump(_ albumID: UInt64) {
        let all = lock.withLock { () -> [String: Int] in
            versions[String(albumID), default: 0] += 1
            return versions
        }
        UserDefaults.standard.set(all, forKey: "coverVersions")
    }
}

/// Your own album covers (SPEC §4 `coverOverride`), decoded once and shown everywhere the album appears.
@MainActor @Observable
final class CoverOverrides {
    static let shared = CoverOverrides()
    private(set) var images: [UInt64: UIImage] = [:]
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        for note in Store.shared.allAlbumNotes() {
            guard let data = note.coverOverride, note.albumID.hasPrefix("album-"), let id = UInt64(note.albumID.dropFirst(6)),
                  let img = UIImage(data: data) else { continue }
            images[id] = img
        }
    }

    func image(_ albumID: UInt64) -> UIImage? {
        load()
        return images[albumID]
    }

    /// Sets (or clears, with nil) your cover for a library album.
    func set(_ data: Data?, for album: Album) {
        let note = Store.shared.albumNoteOrNew("album-\(album.id)", key: album.key)
        if let data, let img = UIImage(data: data) {
            let small = img.preparingThumbnail(of: CGSize(width: 1400, height: 1400)) ?? img
            note.coverOverride = small.jpegData(compressionQuality: 0.88) ?? data
            images[album.id] = small
        } else {
            note.coverOverride = nil
            images[album.id] = nil
        }
        Store.shared.save()
        changed(album.id)
    }

    /// Something about the album's cover changed (still or motion): refresh everything keyed on it.
    func changed(_ albumID: UInt64) {
        CoverVersions.bump(albumID)
        PlaybackCoordinator.shared?.nowPlaying.animated.reset()
        PlaybackCoordinator.shared?.nowPlaying.update()
    }
}
