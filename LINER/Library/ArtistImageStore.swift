import CoreImage
import PhotosUI
import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// Artist portraits: looked up once through the catalogue and kept on disk in black and white (lists, pins) and
/// in colour (the artist page).
/// (The SwiftData `ArtistImage` record from SPEC §4 replaces the small lookup file once models arrive.)
final class ArtistImageStore: @unchecked Sendable {
    static let shared = ArtistImageStore(provider: DeezerCatalog())

    private let provider: any CatalogProvider
    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let lookups = UserDefaults(suiteName: "liner.artistImages") ?? .standard
    private static let context = CIContext()
    /// Retry artists with no photo after a month — catalogues add pictures.
    private static let retryAfter: TimeInterval = 30 * 86_400

    private init(provider: any CatalogProvider) {
        self.provider = provider
        folder = URL.cachesDirectory.appending(path: "LINER/Artists", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cached(_ name: String, colour: Bool = false) -> UIImage? {
        memory.object(forKey: Self.memoryKey(MediaKey.normalise(name), colour: colour) as NSString)
    }

    private static func memoryKey(_ key: String, colour: Bool) -> String { colour ? "\(key).colour" : key }

    /// The artist's photo: black and white (lists, pins), or in full colour (the artist page).
    @concurrent
    func portrait(for name: String, colour: Bool = false) async -> UIImage? {
        let key = MediaKey.normalise(name)
        guard !key.isEmpty else { return nil }
        let mkey = Self.memoryKey(key, colour: colour)
        if let hit = memory.object(forKey: mkey as NSString) { return hit }
        // Your own photo wins over the catalogue's.
        if let own = ownImage(key) {
            let img = colour ? own : (Self.noir(own) ?? own)
            memory.setObject(img, forKey: mkey as NSString)
            return img
        }
        if let data = try? Data(contentsOf: folder.appending(path: "\(mkey).jpg")), let img = UIImage(data: data) {
            memory.setObject(img, forKey: mkey as NSString)
            return img
        }
        guard let original = await original(for: name, key: key) else { return nil }
        // Keep both versions, so either is ready next time.
        store(original, as: Self.memoryKey(key, colour: true))
        let noir = Self.noir(original)
        if let noir { store(noir, as: key) }
        return colour ? original : noir
    }

    // MARK: - Your own photo

    private func ownFile(_ key: String) -> URL { folder.appending(path: "own-\(key).jpg") }

    private func ownImage(_ key: String) -> UIImage? {
        (try? Data(contentsOf: ownFile(key))).flatMap(UIImage.init(data:))
    }

    func hasOwn(_ name: String) -> Bool { FileManager.default.fileExists(atPath: ownFile(MediaKey.normalise(name)).path) }

    /// Saves your own photo for an artist (nil goes back to the catalogue's). Large photos are scaled down.
    @concurrent
    func setOwn(_ data: Data?, for name: String) async {
        let key = MediaKey.normalise(name)
        guard !key.isEmpty else { return }
        if let data, let img = UIImage(data: data) {
            let side = max(img.size.width, img.size.height), limit: CGFloat = 1800
            let out = side > limit ? img.preparingThumbnail(of: CGSize(width: img.size.width * limit / side, height: img.size.height * limit / side)) ?? img : img
            if let jpeg = out.jpegData(compressionQuality: 0.88) { try? jpeg.write(to: ownFile(key), options: .atomic) }
        } else {
            try? FileManager.default.removeItem(at: ownFile(key))
        }
        memory.removeObject(forKey: key as NSString)
        memory.removeObject(forKey: Self.memoryKey(key, colour: true) as NSString)
    }

    private func store(_ image: UIImage, as name: String) {
        if let jpeg = image.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: folder.appending(path: "\(name).jpg"), options: .atomic) }
        memory.setObject(image, forKey: name as NSString)
    }

    /// Downloads the original photo, from the address found last time or a fresh catalogue lookup.
    private func original(for name: String, key: String) async -> UIImage? {
        var url = lookups.string(forKey: "url.\(key)").flatMap(URL.init(string:))
        if url == nil {
            if let missed = lookups.object(forKey: "miss.\(key)") as? Date, Date.now.timeIntervalSince(missed) < Self.retryAfter { return nil }
            switch await provider.artistImage(for: name) {
            case .found(let u): url = u
            case .notFound: lookups.set(Date.now, forKey: "miss.\(key)"); return nil
            case .failed: return nil   // offline or slow: try again next time
            }
        }
        guard let url else { return nil }
        var downloaded: UIImage?
        for _ in 0..<2 where downloaded == nil {
            if let result = try? await URLSession.shared.data(from: url) { downloaded = UIImage(data: result.0) }
        }
        if downloaded != nil { lookups.set(url.absoluteString, forKey: "url.\(key)") }
        return downloaded
    }

    /// CIPhotoEffectNoir plus a touch of contrast (SPEC §3).
    static func noir(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let noir = CIFilter.photoEffectNoir()
        noir.inputImage = input
        let contrast = CIFilter.colorControls()
        contrast.inputImage = noir.outputImage
        contrast.contrast = 1.1
        guard let out = contrast.outputImage, let cg = context.createCGImage(out, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Your own artist photos: picks them from Photos and tells every photo on screen to reload.
@MainActor @Observable
final class ArtistPhotos {
    static let shared = ArtistPhotos()
    private var versions: [String: Int] = [:]

    /// Changes each time the artist's photo is changed, so views and colours taken from it refresh.
    func version(_ name: String) -> Int { versions[MediaKey.normalise(name)] ?? 0 }

    func hasOwn(_ name: String) -> Bool {
        _ = version(name)
        return ArtistImageStore.shared.hasOwn(name)
    }

    func choose(_ item: PhotosPickerItem, for name: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await ArtistImageStore.shared.setOwn(data, for: name)
        versions[MediaKey.normalise(name), default: 0] += 1
    }

    func reset(_ name: String) async {
        await ArtistImageStore.shared.setOwn(nil, for: name)
        versions[MediaKey.normalise(name), default: 0] += 1
    }
}
