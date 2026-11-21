import Foundation

/// Apple Music's own playlists (artist Essentials, editors' playlists like New Music Daily) read from the public
/// music.apple.com pages, which carry their data as JSON. No account or MusicKit is needed; songs then stream by
/// their Apple Music ID like any other. Apple can change these pages at any time, so everything here gives up
/// quietly and returns nothing.
enum AppleMusicWeb {
    struct PlaylistRef: Identifiable, Hashable, Sendable {
        let id: String            // "pl.…"
        let title: String
        let curator: String
        /// Artwork URL with {w}, {h} and {f} to fill in.
        let artworkTemplate: String?
        var shelf: String = ""

        func artwork(_ size: Int) -> URL? {
            guard let t = artworkTemplate else { return nil }
            return URL(string: t.replacingOccurrences(of: "{w}", with: "\(size)").replacingOccurrences(of: "{h}", with: "\(size)")
                .replacingOccurrences(of: "{c}", with: "cc").replacingOccurrences(of: "{f}", with: "jpg"))
        }
        var webURL: URL? { URL(string: "https://music.apple.com/\(AppleMusicWeb.storefront)/playlist/\(id)") }
    }

    struct Playlist: Sendable {
        var ref: PlaylistRef
        var description: String = ""
        var tracks: [AppleCatalog.Track] = []
    }

    static var storefront: String { (Locale.current.region?.identifier ?? "US").lowercased() }
    private static let cache = WebCache()

    /// The playlists on an artist's Apple Music page (Essentials, Deep Cuts, Inspired By…).
    static func artistPlaylists(_ name: String) async -> [PlaylistRef] {
        guard let id = await AppleCatalog.artistID(name) else { return [] }
        return playlists(in: await page("artist/\(id)"))
    }

    /// Editors' playlists from Apple Music's New page, in its order.
    static func editorial() async -> [PlaylistRef] {
        playlists(in: await page("new"))
    }

    /// A playlist's songs (as many as the page carries, usually all of them up to 100).
    static func playlist(_ ref: PlaylistRef) async -> Playlist? {
        guard let json = await page("playlist/\(ref.id)") else { return nil }
        var list = Playlist(ref: ref)
        var seen = Set<Int>()
        walk(json) { o in
            guard let cd = o["contentDescriptor"] as? [String: Any], cd["kind"] as? String == "song",
                  let ids = cd["identifiers"] as? [String: Any], let raw = ids["storeAdamID"] as? String, let id = Int(raw),
                  let title = o["title"] as? String, seen.insert(id).inserted else { return }
            let album = (o["tertiaryLinks"] as? [[String: Any]])?.first
            let albumID = ((((album?["segue"] as? [String: Any])?["destination"] as? [String: Any])?["contentDescriptor"] as? [String: Any])?["identifiers"] as? [String: Any])?["storeAdamID"] as? String
            let artist = ((o["subtitleLinks"] as? [[String: Any]])?.first?["title"] as? String) ?? ref.curator
            let art = ((o["artwork"] as? [String: Any])?["dictionary"] as? [String: Any])?["url"] as? String
            list.tracks.append(AppleCatalog.Track(
                id: id, name: title, artist: artist, album: album?["title"] as? String ?? "", collectionID: albumID.flatMap { Int($0) } ?? 0,
                artwork: art.flatMap { URL(string: $0.replacingOccurrences(of: "{w}", with: "600").replacingOccurrences(of: "{h}", with: "600")
                    .replacingOccurrences(of: "{f}", with: "jpg")) },
                duration: (o["duration"] as? Double ?? 0) / 1000, trackNumber: list.tracks.count + 1, discNumber: 1, genre: "", releaseDate: nil))
        }
        return list.tracks.isEmpty ? nil : list
    }

    // MARK: Reading the pages

    /// Every playlist mentioned on a page, once each, with the shelf it sits on.
    private static func playlists(in json: Any?) -> [PlaylistRef] {
        guard let json else { return [] }
        var found: [PlaylistRef] = [], seen = Set<String>()
        var shelf = ""
        walk(json) { o in
            if let header = (o["header"] as? [String: Any])?["item"] as? [String: Any], let t = header["title"] as? String { shelf = t }
            var id: String?
            if let cd = o["contentDescriptor"] as? [String: Any], cd["kind"] as? String == "playlist" {
                id = (cd["identifiers"] as? [String: Any])?["storeAdamID"] as? String
            } else if let raw = o["id"] as? String, raw.hasPrefix("pl."), o["titleLinks"] != nil {
                id = raw
            }
            guard let id, id.hasPrefix("pl."), !seen.contains(id) else { return }
            let title = (o["title"] as? String) ?? ((o["titleLinks"] as? [[String: Any]])?.first?["title"] as? String)
            guard let title, !title.isEmpty else { return }
            let curator = (o["subtitle"] as? String) ?? ((o["subtitleLinks"] as? [[String: Any]])?.first?["title"] as? String) ?? "Apple Music"
            let art = ((o["artwork"] as? [String: Any])?["dictionary"] as? [String: Any])?["url"] as? String
            seen.insert(id)
            found.append(PlaylistRef(id: id, title: title, curator: curator, artworkTemplate: art, shelf: shelf))
        }
        return found
    }

    private static func walk(_ o: Any, _ visit: ([String: Any]) -> Void) {
        if let d = o as? [String: Any] {
            visit(d)
            for v in d.values { walk(v, visit) }
        } else if let a = o as? [Any] {
            for v in a { walk(v, visit) }
        }
    }

    /// A music.apple.com page's JSON (cached for an hour).
    private static func page(_ path: String) async -> Any? {
        let url = "https://music.apple.com/\(storefront)/\(path)"
        if let hit = await cache.get(url) { return hit.value }
        guard let u = URL(string: url) else { return nil }
        var request = URLRequest(url: u)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "id=\"serialized-server-data\">"),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8)) else { return nil }
        await cache.set(SendableJSON(value: json), for: url)
        return json
    }
}

/// Parsed JSON passed between the cache actor and callers (read only once made).
private struct SendableJSON: @unchecked Sendable { let value: Any }

private actor WebCache {
    private var pages: [String: (Date, SendableJSON)] = [:]
    func get(_ url: String) -> SendableJSON? {
        guard let hit = pages[url], Date.now.timeIntervalSince(hit.0) < 3600 else { return nil }
        return hit.1
    }
    func set(_ json: SendableJSON, for url: String) { pages[url] = (.now, json) }
}
