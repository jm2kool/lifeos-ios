import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Images on cards and files on assignments. Each is kept on the iPhone and uploaded to your folder in the
/// `lumen-files` bucket, so your other devices can fetch it.
@MainActor
enum Files {
    static var root: URL {
        let url = URL.applicationSupportDirectory.appending(path: "files", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func localURL(_ path: String) -> URL { root.appending(path: path) }

    private static var uploaded: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "files.uploaded") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "files.uploaded") }
    }

    static func newPath(folder: String, ext: String) -> String {
        "\(Auth.shared.userID ?? "local")/\(folder)/\(UUID().uuidString.lowercased()).\(ext)"
    }

    /// Saves a picked photo (scaled down to a sensible size) and starts uploading it. Returns its path.
    static func importPhoto(_ item: PhotosPickerItem?, folder: String) async -> String? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return nil }
        return save(image: image, folder: folder)
    }

    static func save(image: UIImage, folder: String) -> String? {
        let scaled = image.scaledDown(maxSide: 1600)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.8) else { return nil }
        let path = newPath(folder: folder, ext: "jpg")
        write(jpeg, to: path)
        Task { await upload(path, mime: "image/jpeg") }
        return path
    }

    /// Copies a file picked in Files into Lumen and starts uploading it.
    static func importFile(_ url: URL, folder: String) -> (path: String, name: String, size: Int, mime: String)? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension.lowercased()
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        let path = newPath(folder: folder, ext: ext)
        write(data, to: path)
        Task { await upload(path, mime: mime) }
        return (path, url.lastPathComponent, data.count, mime)
    }

    private static func write(_ data: Data, to path: String) {
        let url = localURL(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func upload(_ path: String, mime: String? = nil) async -> Bool {
        guard Auth.shared.signedIn, !path.hasPrefix("local/"), !uploaded.contains(path),
              let data = try? Data(contentsOf: localURL(path)) else { return false }
        let type = mime ?? UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        do {
            try await API.upload(path, data: data, mime: type)
            uploaded.insert(path)
            return true
        } catch { return false }
    }

    /// Uploads anything that couldn't go up earlier (say, it was made offline).
    static func uploadPending() async {
        let store = Store.shared
        var paths = store.live(Card.self).flatMap { [$0.frontImage, $0.backImage].compactMap { $0 } }
        paths += store.live(FileAttachment.self).map(\.path)
        for p in Set(paths) where FileManager.default.fileExists(atPath: localURL(p).path) { await upload(p) }
        for a in store.live(FileAttachment.self) where !a.uploaded && uploaded.contains(a.path) { a.uploaded = true }
    }

    /// The file's data, from the iPhone or downloaded (and kept) if it was added on another device.
    static func data(_ path: String) async -> Data? {
        let url = localURL(path)
        if let d = try? Data(contentsOf: url) { return d }
        guard Auth.shared.signedIn, let d = try? await API.download(path) else { return nil }
        write(d, to: path)
        uploaded.insert(path)
        return d
    }

    static func remove(_ path: String) {
        try? FileManager.default.removeItem(at: localURL(path))
        Task { await API.removeFile(path) }
    }
}

extension UIImage {
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > maxSide else { return self }
        let scale = maxSide / side
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// An image from Files, loaded in the background.
struct StoredImage: View {
    var path: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: path) {
            if let d = await Files.data(path), let img = UIImage(data: d) { image = img } else { failed = true }
        }
    }
}
