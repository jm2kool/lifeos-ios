import Foundation

/// The recipe for a mood playlist (SPEC §6.14): small enough for the on-device model, never the library itself.
struct MoodRecipe: Codable, Sendable, Equatable {
    var name: String
    var summary: String
    var moods: [String]
    var genres: [String]
    var energy: Double          // 0 calm … 1 intense
    var eraFrom: Int?
    var eraTo: Int?
    var seedArtists: [String]
    var length: Int             // 15–40

    static let blank = MoodRecipe(name: "My Mood Mix", summary: "", moods: [], genres: [], energy: 0.5, seedArtists: [], length: 25)
}

/// Quick presets (SPEC §6.14).
enum MoodPreset: String, CaseIterable, Identifiable {
    case lateNight = "From my Late Night songs"
    case lovedThisMonth = "Most loved this month"
    case forgotten = "Forgotten favourites"
    var id: String { rawValue }

    var recipe: MoodRecipe {
        switch self {
        case .lateNight:
            MoodRecipe(name: "Late Night", summary: "Your own Late Night songs, and ones that sit with them.", moods: ["Late Night", "Intimate", "Dreamy"],
                       genres: [], energy: 0.3, seedArtists: [], length: 25)
        case .lovedThisMonth:
            MoodRecipe(name: "Loved This Month", summary: "Highly rated songs you've played in the last 30 days.", moods: [], genres: [],
                       energy: 0.5, seedArtists: [], length: 25)
        case .forgotten:
            MoodRecipe(name: "Forgotten Favourites", summary: "Songs you rated highly but haven't played in 90 days.", moods: [], genres: [],
                       energy: 0.5, seedArtists: [], length: 25)
        }
    }
}

/// A rough energy level per genre, the "energy proxy" (no BPM is available without MusicKit).
enum GenreEnergy {
    static func of(_ genre: String) -> Double? {
        let g = genre.lowercased()
        let table: [(String, Double)] = [
            ("metal", 0.95), ("punk", 0.9), ("drum", 0.9), ("edm", 0.9), ("dance", 0.85), ("electronic", 0.75), ("house", 0.8), ("techno", 0.85),
            ("hip", 0.7), ("rap", 0.72), ("rock", 0.72), ("latin", 0.7), ("reggaeton", 0.8), ("k-pop", 0.75), ("pop", 0.6), ("bollywood", 0.62),
            ("punjabi", 0.75), ("indian", 0.55), ("alternative", 0.58), ("indie", 0.5), ("country", 0.5), ("r&b", 0.45), ("soul", 0.45),
            ("soundtrack", 0.4), ("jazz", 0.35), ("folk", 0.3), ("singer", 0.3), ("acoustic", 0.25), ("lo-fi", 0.25), ("classical", 0.2),
            ("ambient", 0.12), ("new age", 0.12),
        ]
        return table.first { g.contains($0.0) }?.1
    }
}
