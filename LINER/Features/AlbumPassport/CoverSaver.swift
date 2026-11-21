import PhotosUI
import SwiftUI

/// A request to change an album's cover (from Customise Album).
struct CoverRequest: Identifiable {
    let album: Album
    let motion: Bool
    var id: String { "\(album.id)-\(motion)" }
}

/// Saves a picked photo or video as an album's cover.
@MainActor
enum CoverSaver {
    static func save(_ item: PhotosPickerItem, for request: CoverRequest) async {
        let album = request.album
        if !request.motion {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            CoverOverrides.shared.set(data, for: album)
            return
        }
        let id = "album-\(album.id)"
        var name: String?
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            name = await MotionCoverImport.importVideo(item, id: id)
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            let tmp = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).gif")
            try? data.write(to: tmp)
            name = await MotionCoverImport.importFile(tmp, id: id)
            try? FileManager.default.removeItem(at: tmp)
        }
        guard let name else { return }
        let note = Store.shared.albumNoteOrNew(id, key: album.key)
        if let old = note.motionCoverFile { try? FileManager.default.removeItem(at: MotionCoverFiles.url(old)) }
        note.motionCoverFile = name
        Store.shared.save()
        CoverOverrides.shared.changed(album.id)
    }

    static func reset(_ album: Album) {
        let note = Store.shared.albumNoteOrNew("album-\(album.id)", key: album.key)
        if let f = note.motionCoverFile { try? FileManager.default.removeItem(at: MotionCoverFiles.url(f)) }
        note.motionCoverFile = nil
        CoverOverrides.shared.set(nil, for: album)
    }
}
