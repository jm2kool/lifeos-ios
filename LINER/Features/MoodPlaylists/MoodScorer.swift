import Foundation

/// Scores every library song against a recipe, in Swift (SPEC §6.14 step 2): mood tags count most, then genre,
/// seed artists, your rating, how much you play it, energy and era. Then diversity: at most 3 per artist and
/// never two from the same album back to back.
enum MoodScorer {
    struct Input: Sendable {
        let songs: [Song]
        let moods: [UInt64: [String]]
        let hearts: [UInt64: Int]
        var preset: String?
    }

    @concurrent
    static func pick(_ recipe: MoodRecipe, from input: Input) async -> [Song] {
        let maxPlays = Double(input.songs.map(\.playCount).max() ?? 1)
        let wantMoods = Set(recipe.moods.map { $0.lowercased() })
        let wantGenres = recipe.genres.map { $0.lowercased() }
        let seeds = Set(recipe.seedArtists.map(MediaKey.normalise))
        let now = Date.now

        func score(_ s: Song) -> Double? {
            let rating = Double(input.hearts[s.id] ?? s.rating)
            switch input.preset {
            case MoodPreset.lovedThisMonth.rawValue:
                guard rating >= 4, let last = s.lastPlayed, now.timeIntervalSince(last) < 30 * 86_400 else { return nil }
            case MoodPreset.forgotten.rawValue:
                guard rating >= 4, (s.lastPlayed.map { now.timeIntervalSince($0) > 90 * 86_400 } ?? true) else { return nil }
            default: break
            }
            var total = 0.0
            let tags = Set((input.moods[s.id] ?? []).map { $0.lowercased() })
            total += 3.0 * Double(tags.intersection(wantMoods).count)
            let genre = s.genre.lowercased()
            if !genre.isEmpty, wantGenres.contains(where: { genre.contains($0) || $0.contains(genre) }) { total += 2 }
            if seeds.contains(MediaKey.normalise(s.albumArtist)) || seeds.contains(MediaKey.normalise(s.artist)) { total += 2.5 }
            total += rating / 5 * 1.5
            total += log1p(Double(s.playCount)) / log1p(maxPlays) * 1.0
            if let e = GenreEnergy.of(s.genre) { total += (1 - abs(e - recipe.energy)) * 1.5 }
            if let from = recipe.eraFrom, let to = recipe.eraTo, let year = s.releaseDate.map({ Calendar.current.component(.year, from: $0) }) {
                total += (from...max(from, to)).contains(year) ? 1 : -1
            }
            // A little randomness so refreshes aren't identical.
            return total + Double.random(in: 0...0.35)
        }

        let ranked = input.songs.compactMap { s in score(s).map { (s, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return diversify(ranked, length: max(15, min(40, recipe.length)))
    }

    static func diversify(_ ranked: [Song], length: Int) -> [Song] {
        var out: [Song] = []
        var perArtist: [String: Int] = [:]
        var pool = ranked
        while out.count < length, !pool.isEmpty {
            guard let i = pool.firstIndex(where: { s in
                (perArtist[s.albumArtist] ?? 0) < 3 && out.last?.albumID != s.albumID
            }) else { break }
            let s = pool.remove(at: i)
            out.append(s)
            perArtist[s.albumArtist, default: 0] += 1
        }
        return out
    }
}
