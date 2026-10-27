import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What Matinee could read from a link: the post's title and caption, who posted it, and the text
/// in its thumbnail (clips often have the film's name burned in).
struct ClipInfo: Hashable {
    var url: URL
    var platform: String              // "YouTube", "X", "TikTok", "Instagram", "Reddit" or the site's name
    var title: String?
    var author: String?
    var caption: String?
    var hashtags: [String] = []
    var thumbnail: URL?
    var thumbnailText: [String] = []

    /// Everything read, as plain lines for the model and the matcher.
    var evidence: String {
        var lines: [String] = []
        if let title { lines.append("Title: \(title)") }
        if let author { lines.append("Posted by: \(author)") }
        if let caption, caption != title { lines.append("Caption: \(caption.prefix(900))") }
        if !hashtags.isEmpty { lines.append("Hashtags: " + hashtags.map { "#\($0)" }.joined(separator: " ")) }
        if !thumbnailText.isEmpty { lines.append("Text in the video frame: " + thumbnailText.joined(separator: " / ")) }
        return lines.joined(separator: "\n")
    }
}

/// A film or show the finder thinks this is, checked against TMDB.
struct FinderMatch: Identifiable, Hashable {
    var film: FilmRef
    var reason: String
    var confidence: Double            // 0…1
    var id: String { film.id }
}

#if canImport(FoundationModels)
@Generable
struct FilmGuesses {
    @Guide(description: "Up to four guesses, most likely first")
    var guesses: [FilmGuess]
}

@Generable
struct FilmGuess {
    @Guide(description: "The film or TV show's official English title, with no year or extra words")
    var title: String
    @Guide(description: "The year it came out, or 0 if unsure")
    var year: Int
    @Guide(description: "true if it's a TV show, false if it's a film")
    var isShow: Bool
    @Guide(description: "A short clause on what gave it away, e.g. 'named in the caption' or 'the hashtag #BreakingBad'")
    var clue: String
}
#endif

/// Finds the film or show behind a clip link, a screenshot, or a description of a scene.
/// Reading links happens through each site's public preview data; guessing happens on the iPhone with
/// Apple Intelligence (or a simpler text matcher without it); TMDB confirms each guess is real.
@MainActor
enum Finder {
    enum Step: Equatable { case reading(String), lookingAtFrame, thinking, checking }

    // MARK: Links

    static func link(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url.flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }
    }

    static func platform(_ url: URL) -> String {
        let h = (url.host ?? "").lowercased()
        if h.contains("youtube.") || h == "youtu.be" { return "YouTube" }
        if h.contains("twitter.") || h == "x.com" || h.hasSuffix(".x.com") { return "X" }
        if h.contains("tiktok.") { return "TikTok" }
        if h.contains("instagram.") { return "Instagram" }
        if h.contains("reddit.") || h == "redd.it" { return "Reddit" }
        if h.contains("facebook.") || h == "fb.watch" { return "Facebook" }
        return h.replacingOccurrences(of: "www.", with: "")
    }

    /// Read a link: titles, captions, hashtags and the thumbnail's text.
    static func read(_ link: URL, step: (Step) -> Void) async -> ClipInfo {
        let url = await resolve(link)
        var info = ClipInfo(url: url, platform: platform(url))
        step(.reading(info.platform))
        switch info.platform {
        case "YouTube": await readYouTube(url, into: &info)
        case "X": await readX(url, into: &info)
        case "TikTok": await readOEmbed("https://www.tiktok.com/oembed?url=", url, into: &info)
        case "Reddit": await readReddit(url, into: &info)
        default: break
        }
        if info.title == nil && info.caption == nil { await readPage(url, into: &info) }
        info.hashtags = Array(Set(info.hashtags + hashtags(in: [info.title, info.caption].compactMap { $0 }.joined(separator: " ")))).sorted()
        if let thumb = info.thumbnail {
            step(.lookingAtFrame)
            if let (data, _) = try? await URLSession.shared.data(from: thumb), let img = UIImage(data: data) {
                info.thumbnailText = await TicketReader.read(img).map(\.text).filter { $0.count >= 2 }.prefix(25).map { $0 }
            }
        }
        return info
    }

    /// Short links (vm.tiktok.com, t.co, bit.ly…) point somewhere else; follow them first.
    private static func resolve(_ url: URL) async -> URL {
        let shorteners = ["vm.tiktok.com", "vt.tiktok.com", "t.co", "bit.ly", "tinyurl.com", "fb.watch", "redd.it", "on.soundcloud.com"]
        guard let host = url.host?.lowercased(), shorteners.contains(host) || (host.hasSuffix("tiktok.com") && url.path.hasPrefix("/t/")) else { return url }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(browser, forHTTPHeaderField: "User-Agent")
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let final = resp.url else { return url }
        return final
    }

    private static func youTubeID(_ url: URL) -> String? {
        if url.host?.contains("youtu.be") == true { return url.pathComponents.dropFirst().first }
        let parts = url.pathComponents
        for key in ["shorts", "embed", "live", "v"] {
            if let i = parts.firstIndex(of: key), i + 1 < parts.count { return parts[i + 1] }
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
    }

    private static func readYouTube(_ url: URL, into info: inout ClipInfo) async {
        let id = youTubeID(url)
        let canonical = id.map { "https://www.youtube.com/watch?v=\($0)" } ?? url.absoluteString
        if let j = await json("https://www.youtube.com/oembed?format=json&url=" + escape(canonical)) {
            info.title = j["title"].str
            info.author = j["author_name"].str
        }
        if let id {
            info.thumbnail = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
            // The watch page carries the full description and the uploader's keywords.
            if let html = await page(canonical) {
                if let d = jsonString(after: "\"shortDescription\":", in: html) { info.caption = d }
                if let k = html.range(of: "\"keywords\":[") {
                    let rest = html[k.upperBound...]
                    if let end = rest.firstIndex(of: "]"),
                       let arr = try? JSONSerialization.jsonObject(with: Data(("[" + rest[..<end] + "]").utf8)) as? [String] {
                        info.hashtags += arr.prefix(15).map { $0.replacingOccurrences(of: " ", with: "") }
                    }
                }
                if info.title == nil { info.title = meta("og:title", in: html) }
            }
        }
    }

    private static func readX(_ url: URL, into info: inout ClipInfo) async {
        guard let id = url.pathComponents.firstIndex(of: "status").flatMap({ i in i + 1 < url.pathComponents.count ? url.pathComponents[i + 1] : nil }) else {
            return
        }
        // fxtwitter's public API gives the post's text and its video's thumbnail.
        if let j = await json("https://api.fxtwitter.com/status/\(id)") {
            let t = j["tweet"]
            info.caption = t["text"].str
            info.author = [t["author"]["name"].str, t["author"]["screen_name"].str.map { "@\($0)" }].compactMap { $0 }.joined(separator: " ")
            info.thumbnail = (t["media"]["videos"].array.first?["thumbnail_url"].str ?? t["media"]["photos"].array.first?["url"].str)
                .flatMap(URL.init(string:))
            if let quote = t["quote"]["text"].str { info.caption = [info.caption, "Quoting: \(quote)"].compactMap { $0 }.joined(separator: "\n") }
        }
        if info.caption == nil, let j = await json("https://publish.twitter.com/oembed?omit_script=1&url=" + escape(url.absoluteString)) {
            info.caption = j["html"].str.map(stripTags)
            info.author = j["author_name"].str
        }
    }

    private static func readOEmbed(_ endpoint: String, _ url: URL, into info: inout ClipInfo) async {
        guard let j = await json(endpoint + escape(url.absoluteString)) else { return }
        info.caption = j["title"].str
        info.author = j["author_name"].str
        info.thumbnail = j["thumbnail_url"].str.flatMap(URL.init(string:))
    }

    private static func readReddit(_ url: URL, into info: inout ClipInfo) async {
        var s = url.absoluteString
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if s.hasSuffix("/") { s.removeLast() }
        guard let j = await json(s + ".json") else { return }
        let post = j.array.first?["data"]["children"].array.first?["data"] ?? J(nil)
        info.title = post["title"].str
        info.caption = post["selftext"].str
        info.author = post["subreddit_name_prefixed"].str
        info.thumbnail = post["preview"]["images"].array.first?["source"]["url"].str
            .map { $0.replacingOccurrences(of: "&amp;", with: "&") }.flatMap(URL.init(string:))
    }

    /// Any other site: its <title> and Open Graph tags.
    private static func readPage(_ url: URL, into info: inout ClipInfo) async {
        guard let html = await page(url.absoluteString) else { return }
        info.title = info.title ?? meta("og:title", in: html) ?? tag("title", in: html)
        info.caption = info.caption ?? meta("og:description", in: html) ?? meta("description", in: html)
        info.thumbnail = info.thumbnail ?? meta("og:image", in: html).flatMap(URL.init(string:))
    }

    // MARK: Finding

    /// The likeliest films and shows for a clip, a description, or text read off a screenshot.
    static func find(clip: ClipInfo?, description: String, screenshotText: [String] = [], step: (Step) -> Void) async -> [FinderMatch] {
        var evidence = clip?.evidence ?? ""
        if !screenshotText.isEmpty { evidence += "\nText in the screenshot: " + screenshotText.prefix(30).joined(separator: " / ") }
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { evidence += "\nWhat the person says about it: \(note)" }
        evidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty else { return [] }

        var guesses: [(title: String, year: Int?, show: Bool?, clue: String, weight: Double)] = []
        #if canImport(FoundationModels)
        if Intelligence.isAvailable {
            step(.thinking)
            let session = LanguageModelSession(instructions: """
                You identify which film or TV show a short video clip, screenshot or description comes from. \
                Use explicit mentions first: titles in captions, hashtags, text on screen, channel names of studios. \
                Then use what you know about actors, characters, famous lines and scenes. Never invent a title. \
                Give official English titles only.
                """)
            if let out = try? await session.respond(to: String(evidence.prefix(3000)), generating: FilmGuesses.self).content {
                for (i, g) in out.guesses.prefix(4).enumerated() where g.title.count >= 2 {
                    guesses.append((g.title, g.year > 1880 ? g.year : nil, g.isShow, g.clue, 1.0 - Double(i) * 0.15))
                }
            }
        }
        #endif
        for (i, t) in heuristicTitles(evidence).prefix(6).enumerated() {
            guesses.append((t, nil, nil, "it's named in the post", 0.55 - Double(i) * 0.06))
        }
        if !note.isEmpty && clip == nil && screenshotText.isEmpty { guesses.append((note, nil, nil, "it matches your description", 0.3)) }

        step(.checking)
        var scored: [String: FinderMatch] = [:]
        var votes: [String: Int] = [:]
        let lowerEvidence = evidence.lowercased()
        // Look every guess up at once.
        var results: [Int: [FilmRef]] = [:]
        await withTaskGroup(of: (Int, [FilmRef]).self) { group in
            for (i, g) in guesses.enumerated() {
                let title = g.title
                group.addTask { (i, (try? await Catalog.search(title)) ?? []) }
            }
            for await (i, found) in group { results[i] = found }
        }
        for (i, g) in guesses.enumerated() {
            guard let found = results[i], !found.isEmpty else { continue }
            for (rank, f) in found.prefix(3).enumerated() {
                if rank == 0 { votes[f.id, default: 0] += 1 }
                var c = g.weight - Double(rank) * 0.2
                if let y = g.year, let fy = f.year { c += abs(y - fy) <= 1 ? 0.15 : -0.2 }
                if let show = g.show { c += show == f.isShow ? 0.05 : -0.1 }
                if lowerEvidence.contains(f.title.lowercased()) && f.title.count > 3 { c += 0.25 }
                if f.poster == nil { c -= 0.3 }
                let reason = g.clue.isEmpty ? "A close match." : g.clue.prefix(1).uppercased() + g.clue.dropFirst()
                if c > (scored[f.id]?.confidence ?? -1) {
                    scored[f.id] = FinderMatch(film: f, reason: reason, confidence: min(1, max(0, c)))
                }
            }
        }
        // Several clues pointing at the same title make it likelier.
        for (id, n) in votes where n > 1 { scored[id]?.confidence = min(1, (scored[id]?.confidence ?? 0) + 0.1 * Double(n - 1)) }
        return scored.values.sorted { $0.confidence > $1.confidence }.prefix(6).map { $0 }
    }

    /// Without the model: likely titles from hashtags, quotes, "Title (2019)", and the parts of a
    /// "Scene | Title | Clip" style video title.
    static func heuristicTitles(_ text: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard t.count >= 2, t.count <= 60, !out.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
            let skip = ["shorts", "short", "fyp", "foryou", "viral", "movie", "movies", "film", "films", "tv", "clip", "scene", "edit",
                        "trending", "reels", "explore", "netflix", "hbo", "series", "show", "funny", "cinema"]
            guard !skip.contains(t.lowercased()) else { return }
            out.append(t)
        }
        // Title (2019)
        for m in matches(#"([A-Z][\w'’:&\-. ]{1,50}?)\s*\((19|20)\d{2}\)"#, in: text) { add(m) }
        // "Quoted titles"
        for m in matches(#"[“"‘']([^“”"‘’']{2,50})[”"’']"#, in: text) { add(m) }
        // Lines like "Title: Scene | Movie | Clip" — not who posted it, or what you typed.
        for line in text.split(separator: "\n")
        where !line.hasPrefix("Posted by:") && !line.hasPrefix("What the person says") && !line.hasPrefix("Hashtags:") {
            let body = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? String(line)
            for part in body.split(whereSeparator: { "|–—•/".contains($0) }) where part.split(separator: " ").count <= 7 { add(String(part)) }
        }
        // #BreakingBad → Breaking Bad
        for tag in hashtags(in: text) { add(splitCamel(tag)) }
        return out
    }

    // MARK: Helpers

    static func hashtags(in text: String) -> [String] {
        matches(#"#([\p{L}\p{N}_]{2,40})"#, in: text)
    }

    private static func splitCamel(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, ch.isUppercase, let prev = out.last, prev.isLowercase { out.append(" ") }
            out.append(ch == "_" ? " " : ch)
        }
        return out
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    private static func escape(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    private static let browser = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func json(_ s: String) async -> J? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Matinee/1.0 (iOS film diary)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return J(obj)
    }

    private static func page(_ s: String) async -> String? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(browser, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Skips YouTube's cookie-consent page in Europe.
        req.setValue("CONSENT=YES+1; SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The JSON string literal right after `marker` in a page, decoded.
    private static func jsonString(after marker: String, in html: String) -> String? {
        guard let r = html.range(of: marker) else { return nil }
        var i = r.upperBound
        guard i < html.endIndex, html[i] == "\"" else { return nil }
        var escaped = false
        i = html.index(after: i)
        let start = html.index(before: i)
        while i < html.endIndex {
            let c = html[i]
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { break }
            i = html.index(after: i)
        }
        guard i < html.endIndex else { return nil }
        let literal = String(html[start...i])
        return (try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed)) as? String
    }

    private static func meta(_ name: String, in html: String) -> String? {
        for pattern in [#"<meta[^>]+(?:property|name)=["']\#(name)["'][^>]+content=["']([^"']*)["']"#,
                        #"<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']\#(name)["']"#] {
            if let m = matches(pattern, in: html).first, !m.isEmpty { return decodeEntities(m) }
        }
        return nil
    }

    private static func tag(_ name: String, in html: String) -> String? {
        matches("<\(name)[^>]*>([^<]{1,300})</\(name)>", in: html).first.map(decodeEntities)
    }

    private static func stripTags(_ html: String) -> String {
        decodeEntities(html.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        var t = s
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&mdash;": "—"] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t
    }
}
