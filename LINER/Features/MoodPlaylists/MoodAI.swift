import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device Apple Intelligence side of mood playlists. Only ever sees your words, a few mood/genre names,
/// and at most ~40 "title – artist" lines — never the library (the model has about a 4K-token context).
@MainActor
enum MoodAI {
    enum State: Equatable { case available, notEnabled, notEligible, notReady, unavailable }

    static var state: State {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(let r):
            switch r {
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .deviceNotEligible: return .notEligible
            case .modelNotReady: return .notReady
            @unknown default: return .unavailable
            }
        @unknown default: return .unavailable
        }
        #else
        return .notEligible
        #endif
    }

    /// Step 1: words (+ chips, seeds, the library's top genres) → recipe.
    static func recipe(vibe: String, chips: [String], seeds: [String], genres: [String]) async throws -> MoodRecipe {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: """
            You design playlist recipes from a listener's description. Moods must come only from this list: \
            \(Moods.all.joined(separator: ", ")). Prefer genres from the listener's library: \(genres.prefix(15).joined(separator: ", ")).
            """)
        var prompt = "Vibe: \(vibe)"
        if !chips.isEmpty { prompt += "\nMoods picked: \(chips.joined(separator: ", "))" }
        if !seeds.isEmpty { prompt += "\nSeed artists: \(seeds.joined(separator: ", "))" }
        let g = try await session.respond(to: prompt, generating: GeneratedRecipe.self).content
        let moods = Array(Set(g.moods.compactMap { m in Moods.all.first { $0.caseInsensitiveCompare(m) == .orderedSame } } + chips))
        return MoodRecipe(name: g.name, summary: g.summary, moods: moods, genres: g.genres, energy: min(1, max(0, g.energy)),
                          eraFrom: g.eraFrom, eraTo: g.eraTo, seedArtists: Array(Set(g.seedArtists + seeds)), length: min(40, max(15, g.length)))
        #else
        throw CancellationError()
        #endif
    }

    /// Step 3 (polish): order the shortlist and name it, in a fresh session.
    static func polish(_ songs: [Song], vibe: String) async -> (title: String, order: [Int])? {
        #if canImport(FoundationModels)
        let list = songs.prefix(40).enumerated().map { "\($0.offset + 1). \($0.element.title) – \($0.element.artist)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: "You order songs so a playlist flows well, and give it a short title.")
        guard let r = try? await session.respond(to: "Vibe: \(vibe)\nSongs:\n\(list)", generating: GeneratedOrder.self).content else { return nil }
        return (r.title, r.order.map { $0 - 1 })
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
struct GeneratedRecipe {
    @Guide(description: "A short, evocative playlist name, 2 to 4 words")
    var name: String
    @Guide(description: "One sentence describing the vibe")
    var summary: String
    @Guide(description: "1 to 4 moods, only from the allowed list")
    var moods: [String]
    @Guide(description: "1 to 3 broad music genres")
    var genres: [String]
    @Guide(description: "Energy from 0 (very calm) to 1 (very intense)", .range(0...1))
    var energy: Double
    @Guide(description: "Earliest release year wanted, if the vibe implies an era")
    var eraFrom: Int?
    @Guide(description: "Latest release year wanted, if the vibe implies an era")
    var eraTo: Int?
    @Guide(description: "Artists the vibe names or strongly implies; may be empty")
    var seedArtists: [String]
    @Guide(description: "Number of songs", .range(15...40))
    var length: Int
}

@Generable
struct GeneratedOrder {
    @Guide(description: "A short playlist title")
    var title: String
    @Guide(description: "Song numbers in the best listening order, each at most once")
    var order: [Int]
}
#endif
