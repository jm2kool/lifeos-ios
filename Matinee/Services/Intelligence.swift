import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A film the on-device model (or the simple matcher, without Apple Intelligence) picked, and why.
struct AIPick: Identifiable, Hashable {
    var film: FilmRef
    var reason: String
    var id: String { film.id }
}

#if canImport(FoundationModels)
@Generable
struct MoodPicks {
    @Guide(description: "Up to three picks from the numbered list, best match first")
    var picks: [MoodPick]
}

@Generable
struct MoodPick {
    @Guide(description: "The number of the title in the list")
    var number: Int
    @Guide(description: "One short, warm sentence on why it suits the mood, under 20 words, no title repeated")
    var reason: String
}

@Generable
struct TicketTitle {
    @Guide(description: "The film's title exactly as printed on the ticket, without format words like IMAX, 3D, Hindi or (UA)")
    var title: String
}
#endif

/// Apple Intelligence, on the phone: nothing you write or watch leaves it. Every feature has a plain fallback
/// for iPhones without Apple Intelligence, so nothing in the app depends on it.
@MainActor
enum Intelligence {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// For Settings: whether it's on, and if not, why.
    static var status: String {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return "On this iPhone"
        case .unavailable(.deviceNotEligible): return "Needs an iPhone 15 Pro or newer"
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings"
        case .unavailable(.modelNotReady): return "Getting ready — try again soon"
        case .unavailable: return "Not available"
        }
        #else
        return "Not available"
        #endif
    }

    // MARK: Ask Matinee — "something short and funny"

    /// Up to three titles from `films` that suit the mood, each with a reason.
    static func pick(mood: String, from films: [FilmRef]) async -> [AIPick] {
        let pool = Array(films.prefix(200))
        guard !pool.isEmpty else { return [] }
        // Fill in genres and runtimes for the ones we'll describe.
        let shortlist = Array(pool.sorted { (FactStore.shared[$0.id] != nil ? 0 : 1) < (FactStore.shared[$1.id] != nil ? 0 : 1) }.prefix(45))
        await FactStore.shared.fill(shortlist, limit: 45)
        #if canImport(FoundationModels)
        if isAvailable {
            let list = shortlist.enumerated().map { "\($0.offset + 1). \(describe($0.element))" }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: """
                You help someone choose what to watch from their own list. Only ever choose titles from the numbered list, \
                by their number. Match the mood, any time limit, and who they're watching with. Be brief and warm.
                """)
            let prompt = "Mood: \(mood)\n\nTheir list:\n\(list)\n\nPick up to three."
            if let out = try? await session.respond(to: prompt, generating: MoodPicks.self).content {
                var seen = Set<Int>()
                let picks = out.picks.compactMap { p -> AIPick? in
                    guard shortlist.indices.contains(p.number - 1), seen.insert(p.number).inserted else { return nil }
                    return AIPick(film: shortlist[p.number - 1], reason: p.reason)
                }
                if !picks.isEmpty { return picks }
            }
        }
        #endif
        return simplePick(mood: mood, from: shortlist)
    }

    /// "Dune (2021) · Sci-Fi, Adventure · 155 min · Denis Villeneuve"
    static func describe(_ f: FilmRef) -> String {
        var parts = [f.title + (f.year.map { " (\($0))" } ?? "") + (f.isShow ? " [TV show]" : "")]
        if let x = FactStore.shared[f.id] {
            if !x.genres.isEmpty { parts.append(x.genres.prefix(3).joined(separator: ", ")) }
            if let m = x.runtime, m > 0 { parts.append(f.isShow ? "\(m) min episodes" : "\(m) min") }
            if let d = x.directors.first { parts.append(d.name) }
        }
        return parts.joined(separator: " · ")
    }

    private static let moodGenres: [(words: [String], genre: String)] = [
        (["funny", "laugh", "comedy", "light", "silly", "fun"], "Comedy"),
        (["scary", "horror", "spooky", "creepy", "halloween"], "Horror"),
        (["tense", "thrill", "edge", "suspense", "gripping"], "Thriller"),
        (["romantic", "romance", "date", "love"], "Romance"),
        (["cry", "sad", "moving", "emotional", "drama"], "Drama"),
        (["action", "explosions", "fight", "adrenaline"], "Action"),
        (["space", "sci-fi", "scifi", "future", "mind", "bending", "trippy"], "Sci-Fi"),
        (["kids", "family", "children"], "Family"),
        (["animated", "animation", "cartoon", "anime"], "Animation"),
        (["mystery", "whodunit", "detective"], "Mystery"),
        (["true", "real", "documentary", "doc"], "Documentary"),
        (["epic", "adventure", "journey", "quest"], "Adventure"),
        (["crime", "heist", "gangster", "mob"], "Crime"),
        (["magic", "fantasy", "dragons"], "Fantasy"),
        (["war", "battle"], "War"),
        (["music", "musical", "band"], "Music"),
    ]

    /// Without Apple Intelligence: match words in the mood to genres and length.
    static func simplePick(mood: String, from films: [FilmRef]) -> [AIPick] {
        let m = mood.lowercased()
        let genres = moodGenres.filter { $0.words.contains { m.contains($0) } }.map(\.genre)
        let short = ["short", "quick", "tired", "school night", "under 2", "90"].contains { m.contains($0) }
        let long = ["long", "epic", "lazy sunday", "marathon"].contains { m.contains($0) }
        let wantsShows = m.contains("show") || m.contains("series") || m.contains("episode")
        let scored = films.map { f -> (FilmRef, Double, String) in
            let x = FactStore.shared[f.id]
            var score = Double.random(in: 0..<0.5)
            var why: [String] = []
            let hits = (x?.genres ?? []).filter { genres.contains($0) }
            if !hits.isEmpty { score += 2 * Double(hits.count); why.append(hits.joined(separator: " and ").lowercased()) }
            if let r = x?.runtime, !f.isShow {
                if short && r <= 105 { score += 1.5; why.append("only \(filmClock(TimeInterval(r * 60)))") }
                if long && r >= 140 { score += 1.5; why.append("a proper \(filmClock(TimeInterval(r * 60))) sit") }
                if short && r > 130 { score -= 2 }
            }
            if wantsShows == f.isShow { score += 0.5 }
            return (f, score, why.joined(separator: ", "))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(3).map { f, _, why in
            AIPick(film: f, reason: why.isEmpty ? "A wildcard from your list." : "\(why.prefix(1).uppercased())\(why.dropFirst()) — fits what you asked for.")
        }
    }

    // MARK: Writing help

    /// Turn rough notes into a short review in the same voice. nil without Apple Intelligence.
    static func writeReview(notes: String, film: FilmRef, score: Double?, liked: Bool) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You tidy up someone's quick notes into a short film diary review, in their own voice and first person. \
            Keep every opinion they gave and add no new facts, plot details or opinions. Two to four sentences. No hashtags, no title line.
            """)
        var prompt = "Film: \(film.title)\(film.year.map { " (\($0))" } ?? "")\n"
        if let score { prompt += "Their score: \(Int(score))/100 (\(Score.word(score)))\n" }
        if liked { prompt += "They loved it.\n" }
        prompt += "Their notes: \(notes)"
        return try? await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    /// A short, upbeat paragraph about your year, from the numbers in Year in Review.
    static func yearSummary(_ review: YearReview) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable, review.filmCount > 0 else { return nil }
        let session = LanguageModelSession(instructions: """
            You write the last card of someone's year-in-film recap. Speak to them as "you". Three sentences, warm and a little playful, \
            using only the facts given. Don't list every number; pick the most telling ones.
            """)
        return try? await session.respond(to: review.factSheet).content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    /// One or two sentences on how two people's taste lines up.
    static func matchBlurb(me: String, them: String, theirName: String, shared: [String], percent: Int) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You describe how two people's film taste compares, in two short sentences, speaking to the first person as "you". \
            Friendly, specific, using only the facts given. Suggest what kind of film night would suit them both.
            """)
        let prompt = """
            Taste match: \(percent)%
            You: \(me)
            \(theirName): \(them)
            In common: \(shared.isEmpty ? "nothing yet" : shared.joined(separator: ", "))
            """
        return try? await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    /// The film's title from the text on a cinema ticket. nil without Apple Intelligence or when unsure.
    static func ticketTitle(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You read the text of a cinema ticket or booking confirmation and find the film's title. \
            Ignore the cinema, screen, seats, prices, times and codes.
            """)
        guard let t = try? await session.respond(to: String(text.prefix(1500)), generating: TicketTitle.self).content.title else { return nil }
        let clean = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count >= 2 ? clean : nil
        #else
        return nil
        #endif
    }
}
