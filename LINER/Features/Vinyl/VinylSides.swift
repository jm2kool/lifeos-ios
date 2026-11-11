import SwiftUI

/// One side of a record: its letter and which of the record's tracks are on it.
struct VinylSide: Hashable, Sendable {
    let name: String
    let range: Range<Int>
}

/// Your own sides for records: which songs go on Side A, B, C… for each album or mixtape. Kept as lists of song
/// IDs per record (in UserDefaults). Songs you haven't placed (new ones, or ones only on the full album) go on
/// the last side.
@MainActor @Observable
final class VinylSides {
    static let shared = VinylSides()
    static let storageKey = "vinylSides"
    private(set) var layouts: [String: [[String]]]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey) ?? Data()
        layouts = Coding.decode([String: [[String]]].self, data) ?? [:]
    }

    func layout(_ recordID: String) -> [[String]]? { layouts[recordID] }

    /// Saves (or, with nil, forgets) your sides for a record.
    func set(_ sides: [[String]]?, for recordID: String) {
        layouts[recordID] = sides
        save()
    }

    /// Every record's sides, for backups.
    func replaceAll(_ all: [String: [[String]]]) {
        layouts.merge(all) { _, new in new }
        save()
    }

    private func save() { UserDefaults.standard.set(Coding.encode(layouts), forKey: Self.storageKey) }

    /// The record's songs in side order, and where each side starts.
    func arrange(_ tracks: [QueueItem], for recordID: String) -> (tracks: [QueueItem], sides: [VinylSide]) {
        guard let layout = layouts[recordID], !layout.isEmpty else { return (tracks, []) }
        var remaining = tracks
        var groups: [[QueueItem]] = layout.map { ids in
            ids.compactMap { id in remaining.firstIndex { $0.id == id }.map { remaining.remove(at: $0) } }
        }
        groups[groups.count - 1].append(contentsOf: remaining)
        groups = groups.filter { !$0.isEmpty }
        var ordered: [QueueItem] = []
        var sides: [VinylSide] = []
        for (i, group) in groups.enumerated() {
            sides.append(VinylSide(name: Self.letter(i), range: ordered.count..<(ordered.count + group.count)))
            ordered += group
        }
        return (ordered, sides)
    }

    /// Side A, B, C… (then round again after Z).
    nonisolated static func letter(_ i: Int) -> String { String(Character(UnicodeScalar(UInt8(65 + i % 26)))) }

    /// The usual record: the first half on Side A, the rest on Side B.
    nonisolated static func halves(_ n: Int) -> [VinylSide] {
        let half = (n + 1) / 2
        return n > 1 ? [VinylSide(name: "A", range: 0..<half), VinylSide(name: "B", range: half..<n)] : [VinylSide(name: "A", range: 0..<n)]
    }
}

extension VinylRecord {
    /// The record with your sides applied: its songs in side order.
    @MainActor func sided() -> VinylRecord {
        let arranged = VinylSides.shared.arrange(tracks, for: id)
        var copy = VinylRecord(id: id, title: title, artist: artist, year: year, albumID: albumID, coverData: coverData,
                               tracks: arranged.tracks, source: source)
        copy.sides = arranged.sides
        return copy
    }

    @MainActor static func mixtape(_ m: Mixtape) -> VinylRecord {
        VinylRecord(id: "mixtape-\(m.id)", title: m.title, artist: m.artist, year: m.year, albumID: nil, coverData: m.coverImage,
                    tracks: m.orderedTracks.map { .local(TrackResolver.local($0)) }, source: .mixtape(m)).sided()
    }
}
