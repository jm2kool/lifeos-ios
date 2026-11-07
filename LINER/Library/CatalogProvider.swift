import Foundation

/// Where artist photos and other catalogue facts come from. Only Deezer for now (free, no key);
/// a paid Apple Music path could slot in here later (SPEC §1).
protocol CatalogProvider: Sendable {
    var sourceName: String { get }
    /// A large portrait for the artist, or nil when the catalogue has no real photo.
    func artistImageURL(for name: String) async -> URL?
}

/// Deezer's public API: `search/artist` → `picture_xl`. Spaced out to stay well under its 50 requests / 5 s limit.
struct DeezerCatalog: CatalogProvider {
    let sourceName = "Deezer"
    private static let limiter = RateLimiter(gap: .milliseconds(150))

    private struct Response: Decodable {
        struct Artist: Decodable { let name: String; let picture_xl: String? }
        let data: [Artist]
    }

    func artistImageURL(for name: String) async -> URL? {
        var parts = URLComponents(string: "https://api.deezer.com/search/artist")!
        parts.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "limit", value: "5")]
        guard let url = parts.url else { return nil }
        await Self.limiter.wait()
        guard let result = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: result.0) else { return nil }
        let wanted = MediaKey.normalise(name)
        // Only accept a matching name, so a wrong artist's face never shows up.
        guard let match = decoded.data.first(where: { MediaKey.normalise($0.name) == wanted }),
              let picture = match.picture_xl, !picture.contains("/artist//") else { return nil }
        return URL(string: picture)
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
