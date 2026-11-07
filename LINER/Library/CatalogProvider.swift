import Foundation

/// Where artist photos and other catalogue facts come from. Only Deezer for now (free, no key);
/// a paid Apple Music path could slot in here later (SPEC §1).
protocol CatalogProvider: Sendable {
    var sourceName: String { get }
    func artistImage(for name: String) async -> CatalogResult
}

/// A lookup's outcome: only `.notFound` is remembered as "no photo"; a failed request is simply tried again later.
enum CatalogResult: Sendable { case found(URL), notFound, failed }

/// Deezer's public API: `search/artist` → `picture_xl`. Spaced out to stay well under its 50 requests / 5 s limit.
struct DeezerCatalog: CatalogProvider {
    let sourceName = "Deezer"
    private static let limiter = RateLimiter(gap: .milliseconds(150))

    private struct Response: Decodable {
        struct Artist: Decodable { let name: String; let picture_xl: String? }
        let data: [Artist]
    }

    func artistImage(for name: String) async -> CatalogResult {
        var parts = URLComponents(string: "https://api.deezer.com/search/artist")!
        parts.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "limit", value: "5")]
        guard let url = parts.url else { return .failed }
        await Self.limiter.wait()
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: result.0) else { return .failed }
        let wanted = MediaKey.normalise(name)
        // Only accept a matching name, so a wrong artist's face never shows up.
        guard let match = decoded.data.first(where: { MediaKey.normalise($0.name) == wanted }),
              let picture = match.picture_xl, !picture.contains("/artist//"), let pictureURL = URL(string: picture) else { return .notFound }
        return .found(pictureURL)
    }
}

/// Hands out evenly spaced time slots, so bursts of requests queue politely.
actor RateLimiter {
    private let gap: Duration
    private var next = ContinuousClock.now

    init(gap: Duration) { self.gap = gap }

    func wait() async {
        let now = ContinuousClock.now
        let slot = max(now, next)
        next = slot + gap
        try? await Task.sleep(until: slot, clock: .continuous)
    }
}
