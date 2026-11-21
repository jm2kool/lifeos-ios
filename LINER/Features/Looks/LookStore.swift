import SwiftUI

/// Your logos, logo colours and positions, album fonts, cover layouts and pin covers, kept as one small JSON file
/// with the logo images beside it in Application Support/LINER/Looks. Views read it directly and redraw when it
/// changes.
@MainActor @Observable
final class LookStore {
    static let shared = LookStore()

    private(set) var looks: [String: SubjectLook] = [:]
    /// Bumped whenever a logo image changes, so cached images are dropped.
    private(set) var revision = 0
    @ObservationIgnored private var images: [String: UIImage] = [:]
    @ObservationIgnored private let folder: URL
    private var file: URL { folder.appending(path: "looks.json") }
    var logos: URL { folder.appending(path: "Logos", directoryHint: .isDirectory) }

    private init() {
        folder = URL.applicationSupportDirectory.appending(path: "LINER/Looks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder.appending(path: "Logos"), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: folder.appending(path: "looks.json")),
           let saved = try? JSONDecoder().decode([String: SubjectLook].self, from: data) {
            looks = saved
        }
    }

    func look(_ key: String) -> SubjectLook { looks[key] ?? SubjectLook() }

    /// Changes one look and saves.
    func update(_ key: String, _ change: (inout SubjectLook) -> Void) {
        var l = look(key)
        change(&l)
        looks[key] = l.isEmpty ? nil : l
        save()
    }

    // MARK: Logos

    /// Your logo for this album, release or artist, if you added one.
    func logo(_ key: String) -> UIImage? {
        guard let name = looks[key]?.logoFile else { return nil }
        if let hit = images[name] { return hit }
        guard let img = UIImage(contentsOfFile: logos.appending(path: name).path(percentEncoded: false)) else { return nil }
        images[name] = img
        return img
    }

    /// Saves a logo (a PNG with transparency). Keeps the colour and position you had.
    func setLogo(_ png: Data, for key: String) {
        let name = "\(UUID().uuidString).png"
        guard (try? png.write(to: logos.appending(path: name), options: .atomic)) != nil else { return }
        let old = looks[key]?.logoFile
        update(key) { $0.logoFile = name }
        if let old { removeFile(old) }
        revision += 1
    }

    func removeLogo(_ key: String) {
        let old = looks[key]?.logoFile
        update(key) { $0.logoFile = nil; $0.placement = nil; $0.tint = .original }
        if let old { removeFile(old) }
        revision += 1
    }

    private func removeFile(_ name: String) {
        images[name] = nil
        try? FileManager.default.removeItem(at: logos.appending(path: name))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(looks) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: Backups

    /// Every look with its logo image, for the backup file.
    func exported() -> [String: BackupFile.LookItem] {
        looks.mapValues { l in
            BackupFile.LookItem(look: Coding.encode(l), logo: l.logoFile.flatMap { try? Data(contentsOf: logos.appending(path: $0)) })
        }
    }

    /// Brings looks back from a backup (ones you've set since are replaced by the backup's).
    func restore(_ items: [String: BackupFile.LookItem]) {
        for (key, item) in items {
            guard var l = Coding.decode(SubjectLook.self, item.look) else { continue }
            l.logoFile = nil
            if let png = item.logo {
                let name = "\(UUID().uuidString).png"
                if (try? png.write(to: logos.appending(path: name), options: .atomic)) != nil { l.logoFile = name }
            }
            if let old = looks[key]?.logoFile { removeFile(old) }
            looks[key] = l
        }
        save()
        revision += 1
    }
}

extension LookStore {
    /// The look of the album a queue item comes from (the lead album for grouped editions, the release for
    /// Apple Music songs you don't have).
    func key(for item: QueueItem, snapshot: LibrarySnapshot) -> String {
        guard let song = item.song else { return item.artworkKey }
        let catalogFlag: UInt64 = 1 << 61
        if song.albumID & catalogFlag != 0 { return LookKey.release(Int(song.albumID & ~catalogFlag)) }
        return LookKey.album(snapshot.album(song.albumID)?.id ?? song.albumID)
    }

    /// The album's font for the player, when you chose to use it there.
    func playerFace(for item: QueueItem, snapshot: LibrarySnapshot) -> AlbumFace? {
        guard let face = look(key(for: item, snapshot: snapshot)).face, face.inPlayer else { return nil }
        return face
    }
}
