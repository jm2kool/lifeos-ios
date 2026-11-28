import CoreImage
import SwiftUI
import UIKit

/// Keeps every album's Studio look (one JSON file) and its pictures (the Studio folder), and answers the
/// places that draw covers: the library grid, the album page, the player and Lock Screen, and Home's pins.
/// Albums are keyed "album-<persistentID>", like `AlbumNote`.
@MainActor @Observable
final class StudioStore {
    static let shared = StudioStore()
    private(set) var looks: [String: StudioLook] = [:]
    @ObservationIgnored private var images: [String: UIImage] = [:]
    @ObservationIgnored private var loaded = false

    static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "LINER/Studio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static var file: URL { folder.appending(path: "looks.json") }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.file), let all = try? JSONDecoder().decode([String: StudioLook].self, from: data) {
            looks = all
        }
    }

    func look(_ albumID: UInt64) -> StudioLook? {
        load()
        return looks["album-\(albumID)"]
    }

    /// Saves a look (or removes it when it's back to the plain album) and tells every cover cache.
    func save(_ look: StudioLook?, for albumID: UInt64) {
        load()
        let old = looks["album-\(albumID)"]
        looks["album-\(albumID)"] = look?.isPlain == true ? nil : look
        if let data = try? JSONEncoder().encode(looks) { try? data.write(to: Self.file, options: .atomic) }
        if old?.covers != look?.covers || old?.places != look?.places {
            CoverOverrides.shared.changed(albumID)
            removeUnused(old: old, new: look)
        }
    }

    // MARK: Covers for each place

    /// The cover picture this place shows instead of the album's own, if Studio changed it.
    func still(_ albumID: UInt64, _ place: StudioPlace) -> UIImage? {
        guard let cover = look(albumID)?.cover(for: place), let name = cover.rendered else { return nil }
        return image(name)
    }

    /// A video cover for this place (a file in MotionCoverFiles).
    func video(_ albumID: UInt64, _ place: StudioPlace) -> String? {
        guard let cover = look(albumID)?.cover(for: place), cover.kind == .video else { return nil }
        return cover.video
    }

    func motion(_ albumID: UInt64) -> StudioMotion { look(albumID)?.motion ?? .off }

    func image(_ name: String) -> UIImage? {
        if let hit = images[name] { return hit }
        guard let data = try? Data(contentsOf: Self.folder.appending(path: name)), let img = UIImage(data: data) else { return nil }
        images[name] = img
        return img
    }

    // MARK: Files

    /// Saves a picture to the Studio folder and returns its file name.
    func store(_ image: UIImage, png: Bool = false) -> String? {
        let name = "\(UUID().uuidString).\(png ? "png" : "jpg")"
        guard let data = png ? image.pngData() : image.jpegData(compressionQuality: 0.9) else { return nil }
        do { try data.write(to: Self.folder.appending(path: name)) } catch { return nil }
        images[name] = image
        return name
    }

    /// Deletes pictures and videos the old look had and the new one doesn't (also used to throw away a draft).
    func removeUnused(old: StudioLook?, new: StudioLook?) {
        func files(_ l: StudioLook?) -> Set<String> {
            guard let l else { return [] }
            return Set(l.covers.flatMap { [$0.source, $0.rendered] }.compactMap { $0 } + [l.title.logoFile].compactMap { $0 })
        }
        for name in files(old).subtracting(files(new)) {
            images[name] = nil
            try? FileManager.default.removeItem(at: Self.folder.appending(path: name))
        }
        let oldVideos = Set(old?.covers.compactMap(\.video) ?? []), newVideos = Set(new?.covers.compactMap(\.video) ?? [])
        for name in oldVideos.subtracting(newVideos) { try? FileManager.default.removeItem(at: MotionCoverFiles.url(name)) }
    }
}

/// Renders a Studio cover to the square that's shown everywhere: cropped (zoomed and moved) or extended (the
/// whole picture fitted, with the edges filled by the same picture stretched and blurred).
enum StudioRender {
    static let side: CGFloat = 1400

    static func square(_ image: UIImage, zoom: Double, offsetX: Double, offsetY: Double, extend: Bool) -> UIImage {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let w = image.size.width, h = image.size.height
            guard w > 0, h > 0 else { return }
            if extend {
                // Behind: the picture filling the square, blurred; in front: the whole picture.
                let fill = max(side / w, side / h)
                let back = CGRect(x: (side - w * fill) / 2, y: (side - h * fill) / 2, width: w * fill, height: h * fill)
                if let blurred = blur(image) { blurred.draw(in: back) } else { image.draw(in: back) }
                UIColor.black.withAlphaComponent(0.12).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let fit = min(side / w, side / h) * zoom
                image.draw(in: CGRect(x: (side - w * fit) / 2 + offsetX * side, y: (side - h * fit) / 2 + offsetY * side,
                                      width: w * fit, height: h * fit))
            } else {
                let scale = max(side / w, side / h) * max(1, zoom)
                let dw = w * scale, dh = h * scale
                // Keep the picture covering the square however far it's moved.
                let x = min(0, max(side - dw, (side - dw) / 2 - offsetX * dw))
                let y = min(0, max(side - dh, (side - dh) / 2 - offsetY * dh))
                image.draw(in: CGRect(x: x, y: y, width: dw, height: dh))
            }
        }
    }

    private static func blur(_ image: UIImage) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: max(image.size.width, image.size.height) / 30).cropped(to: ci.extent)
        guard let cg = CIContext().createCGImage(out, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
