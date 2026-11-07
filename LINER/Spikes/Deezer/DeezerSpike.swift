import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Spike C: Deezer's public API as the free source of artist portraits (no key needed).
@MainActor @Observable
final class DeezerSpike {
    static let shared = DeezerSpike()

    struct Match: Identifiable {
        let id = UUID()
        let asked: String
        let found: String?
        let fans: Int
        let url: URL?
        /// Deezer returns a grey silhouette when it has no photo; its URL has an empty hash ("/artist//").
        var isPlaceholder: Bool { url?.absoluteString.contains("/artist//") ?? true }
        var nameMatches: Bool { found.map { DeezerSpike.normalise($0) == DeezerSpike.normalise(asked) } ?? false }
    }

    private(set) var matches: [Match] = []
    private(set) var portrait: UIImage?
    private(set) var running = false
    private let report = SpikeReport.shared

    private struct Response: Decodable {
        struct Artist: Decodable { let name: String; let picture_xl: String?; let nb_fan: Int? }
        let data: [Artist]
    }

    func lookUp(_ name: String) async -> Match {
        var parts = URLComponents(string: "https://api.deezer.com/search/artist")!
        parts.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "limit", value: "5")]
        do {
            let (data, response) = try await URLSession.shared.data(from: parts.url!)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            // Prefer an exact name match over Deezer's first result.
            let best = decoded.data.first { Self.normalise($0.name) == Self.normalise(name) } ?? decoded.data.first
            if code != 200 { report.log(.deezer, "HTTP \(code) for \(name)") }
            return Match(asked: name, found: best?.name, fans: best?.nb_fan ?? 0, url: best?.picture_xl.flatMap(URL.init(string:)))
        } catch {
            report.log(.deezer, "\(name): \(error.localizedDescription)")
            return Match(asked: name, found: nil, fans: 0, url: nil)
        }
    }

    /// Looks up the given artists (your top 10 by default) and reports the hit rate.
    func run(_ names: [String]) async {
        running = true
        defer { running = false }
        matches = []
        let clock = ContinuousClock()
        let start = clock.now
        for name in names { matches.append(await lookUp(name)) }
        let elapsed = clock.now - start
        let good = matches.filter { $0.nameMatches && !$0.isPlaceholder }.count
        for m in matches {
            report.log(.deezer, "\(m.asked) → \(m.found ?? "no result")\(m.nameMatches ? "" : " (name differs)")\(m.isPlaceholder ? " · NO PHOTO" : " · photo") · \(m.fans.formatted()) fans")
        }
        report.log(.deezer, "\(good)/\(matches.count) with a real photo and matching name, in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))")
        if let first = matches.first(where: { !$0.isPlaceholder })?.url { await showPortrait(first) }
        let rate = matches.isEmpty ? 0 : Double(good) / Double(matches.count)
        report.set(.deezer, rate >= 0.7 ? .works : (good > 0 ? .partial : .fails), because: "\(good)/\(matches.count) usable")
    }

    func showPortrait(_ url: URL) async {
        guard let result = try? await URLSession.shared.data(from: url), let image = UIImage(data: result.0) else { return }
        portrait = Self.noir(image)
        report.log(.deezer, "Portrait \(Int(image.size.width))×\(Int(image.size.height)) px, desaturated")
    }

    /// Black and white with a little extra contrast, as the artist page will show it.
    static func noir(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let noir = CIFilter.photoEffectNoir()
        noir.inputImage = input
        let contrast = CIFilter.colorControls()
        contrast.inputImage = noir.outputImage
        contrast.contrast = 1.1
        guard let out = contrast.outputImage, let cg = CIContext().createCGImage(out, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    nonisolated static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }
}
