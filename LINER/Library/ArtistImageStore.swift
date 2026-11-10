import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Black-and-white artist portraits: looked up once through the catalogue, desaturated, and kept on disk.
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

    func cached(_ name: String) -> UIImage? { memory.object(forKey: MediaKey.normalise(name) as NSString) }

    @concurrent
    func portrait(for name: String) async -> UIImage? {
        let key = MediaKey.normalise(name)
        guard !key.isEmpty else { return nil }
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = folder.appending(path: "\(key).jpg")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }
        if let missed = lookups.object(forKey: "miss.\(key)") as? Date, Date.now.timeIntervalSince(missed) < Self.retryAfter { return nil }

        let url: URL
        switch await provider.artistImage(for: name) {
        case .found(let u): url = u
        case .notFound: lookups.set(Date.now, forKey: "miss.\(key)"); return nil
        case .failed: return nil   // offline or slow: try again next time
        }
        var downloaded: UIImage?
        for _ in 0..<2 where downloaded == nil {
            if let result = try? await URLSession.shared.data(from: url) { downloaded = UIImage(data: result.0) }
        }
        guard let original = downloaded, let noir = Self.noir(original) else { return nil }
        lookups.set(url.absoluteString, forKey: "url.\(key)")
        if let jpeg = noir.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: file, options: .atomic) }
        memory.setObject(noir, forKey: key as NSString)
        return noir
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
