import Foundation

/// Folds editions of one album ("WILD", "WILD (Deluxe)", "WILD [Expanded Edition]") into a single album.
/// The edition with the most songs leads (its cover, order and ID); songs only on the others are added after
/// its tracklist, and songs on several editions appear once. Adding a bigger edition later makes it the lead.
enum AlbumEditions {
    /// Turned off in Settings → Library to see every edition on its own.
    static var isOn: Bool { UserDefaults.standard.object(forKey: "groupAlbumEditions") as? Bool ?? true }

    /// Words that mark a bracket or " - " suffix as an edition rather than part of the name.
    /// ("Version" alone is left out so re-recordings such as "(Taylor's Version)" stay separate.)
    private static let markers = ["deluxe", "expanded", "edition", "remaster", "anniversary", "bonus", "special",
                                  "extended", "platinum", "complete", "collector", "reissue", "explicit", "clean",
                                  "super", "tour", "bonustrack", "japan"]

    /// The album's name without edition suffixes: "WILD (Deluxe)" → "WILD".
    static func baseTitle(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespaces)
        while true {
            let before = t
            for (open, close) in [("(", ")"), ("[", "]")] where t.hasSuffix(close) {
                if let r = t.range(of: open, options: .backwards), r.lowerBound > t.startIndex,
                   isEdition(String(t[r.upperBound...].dropLast())) {
                    t = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
            for dash in [" - ", " – ", " — "] {
                if let r = t.range(of: dash, options: .backwards), isEdition(String(t[r.upperBound...])) {
                    t = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
            if t == before || t.isEmpty { return t.isEmpty ? title : t }
        }
    }

    private static func isEdition(_ text: String) -> Bool {
        let n = MediaKey.normalise(text)
        return !n.isEmpty && markers.contains { n.contains($0) }
    }

    /// Merges editions. Returns the albums, the songs with their album ID pointing at the lead edition,
    /// and a map from each folded-in edition's ID to the lead's ID. `auto` groups by name; `userGroups` are albums
    /// you grouped yourself (always together), and albums in `split` are never grouped by name.
    static func merge(_ albums: [Album], songs: [Song], auto: Bool = true, userGroups: [[UInt64]] = [],
                      split: Set<UInt64> = []) -> (albums: [Album], songs: [Song], aliases: [UInt64: UInt64]) {
        var mine: [UInt64: Int] = [:]
        for (i, ids) in userGroups.enumerated() { for id in ids { mine[id] = i } }
        var groups: [String: [Album]] = [:]
        for a in albums where !a.isSingle {
            let key: String
            if let g = mine[a.id] { key = "user|\(g)" }
            else if auto && !split.contains(a.id) { key = MediaKey.normalise(a.artist) + "|" + MediaKey.normalise(baseTitle(a.title)) }
            else { continue }
            groups[key, default: []].append(a)
        }
        let songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var aliases: [UInt64: UInt64] = [:]
        var merged: [UInt64: Album] = [:]
        for (_, editions) in groups where editions.count > 1 {
            let ordered = editions.sorted { ($0.songCount, $1.id) > ($1.songCount, $0.id) }
            let lead = ordered[0]
            var seen = Set<String>()
            var ids: [UInt64] = []
            for e in ordered {
                for id in e.songIDs {
                    guard let s = songsByID[id], seen.insert(MediaKey.normalise(s.title)).inserted else { continue }
                    ids.append(id)
                }
                if e.id != lead.id { aliases[e.id] = lead.id }
            }
            let tracks = ids.compactMap { songsByID[$0] }
            let rated = tracks.filter { $0.rating > 0 }
            merged[lead.id] = Album(
                id: lead.id, title: baseTitle(lead.title), artist: lead.artist,
                genre: lead.genre.isEmpty ? ordered.first { !$0.genre.isEmpty }?.genre ?? "" : lead.genre,
                year: ordered.compactMap(\.year).min(), songIDs: ids,
                playCount: ordered.reduce(0) { $0 + $1.playCount },
                duration: tracks.reduce(0) { $0 + $1.duration },
                dateAdded: ordered.map(\.dateAdded).max() ?? lead.dateAdded,
                rating: rated.isEmpty ? 0 : Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count),
                editionIDs: ordered.map(\.id))
        }
        guard !aliases.isEmpty else { return (albums, songs, [:]) }
        let outAlbums = albums.compactMap { a -> Album? in aliases[a.id] != nil ? nil : (merged[a.id] ?? a) }
        let outSongs = songs.map { s -> Song in
            guard let lead = aliases[s.albumID] else { return s }
            var copy = s
            copy.albumID = lead
            return copy
        }
        return (outAlbums, outSongs, aliases)
    }
}

/// Albums you grouped yourself (versions the automatic grouping missed) and editions you split apart again.
/// Kept as persistent IDs in UserDefaults, so the scanner can read them off the main thread.
enum AlbumGroups {
    static let groupsKey = "albumGroups", splitKey = "albumGroupsSplit"

    /// Your groups, each a list of album persistent IDs.
    static var groups: [[UInt64]] {
        ((UserDefaults.standard.array(forKey: groupsKey) as? [[String]]) ?? []).map { $0.compactMap { UInt64($0) } }.filter { $0.count > 1 }
    }

    /// Albums never grouped by name (you separated them).
    static var split: Set<UInt64> { Set((UserDefaults.standard.stringArray(forKey: splitKey) ?? []).compactMap { UInt64($0) }) }

    /// Groups these albums (every edition of each) into one; groups already touching them join in.
    static func group(_ ids: [UInt64]) {
        var all = Set(ids)
        var others: [[UInt64]] = []
        for g in groups { if g.contains(where: { all.contains($0) }) { all.formUnion(g) } else { others.append(g) } }
        save(others + [Array(all).sorted()], split: split.subtracting(all))
    }

    /// Separates an album's editions again: your group goes, and they're no longer grouped by name.
    static func ungroup(_ ids: [UInt64]) {
        let set = Set(ids)
        save(groups.filter { g in !g.contains { set.contains($0) } }, split: split.union(set))
    }

    /// Forgets every group and separation you made.
    static func reset() { save([], split: []) }

    static var isEmpty: Bool { groups.isEmpty && split.isEmpty }

    /// For backups: the groups and separations as strings.
    static var stored: (groups: [[String]], split: [String]) {
        (groups.map { $0.map { String($0) } }, split.map { String($0) })
    }

    static func restore(groups: [[String]], split: [String]) {
        save(groups.map { $0.compactMap { UInt64($0) } } + self.groups, split: self.split.union(split.compactMap { UInt64($0) }))
    }

    private static func save(_ groups: [[UInt64]], split: Set<UInt64>) {
        UserDefaults.standard.set(groups.filter { $0.count > 1 }.map { $0.map { String($0) } }, forKey: groupsKey)
        UserDefaults.standard.set(split.map { String($0) }, forKey: splitKey)
    }
}
