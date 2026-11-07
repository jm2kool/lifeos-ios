import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The app's mood list (SPEC §6.8). The model must only pick from these.
enum Moods {
    static let all = ["Euphoric", "Melancholic", "Nostalgic", "Intimate", "Dreamy", "Dangerous",
                      "Healing", "Late Night", "Confident", "Bittersweet", "Energetic", "Calm"]
}

#if canImport(FoundationModels)
/// Step 1 of the mood playlist design: a small recipe, never the library itself.
@Generable
struct SpikeRecipe {
    @Guide(description: "A short, evocative playlist name, 2 to 4 words")
    var name: String
    @Guide(description: "One sentence describing the vibe")
    var summary: String
    @Guide(description: "1 to 4 moods, chosen ONLY from: Euphoric, Melancholic, Nostalgic, Intimate, Dreamy, Dangerous, Healing, Late Night, Confident, Bittersweet, Energetic, Calm")
    var moods: [String]
    @Guide(description: "1 to 3 broad music genres")
    var genres: [String]
    @Guide(description: "Energy from 0 (very calm) to 1 (very intense)", .range(0...1))
    var energy: Double
    @Guide(description: "Number of songs", .range(15...40))
    var length: Int
}

/// Step 3 (optional polish): reorder a shortlist the app already scored.
@Generable
struct SpikeOrder {
    @Guide(description: "A playlist title")
    var title: String
    @Guide(description: "The candidate numbers in the best listening order, using each number at most once")
    var order: [Int]
}
#endif

/// Spike B: is the on-device model there, and how fast is it for our two-step design?
@MainActor @Observable
final class IntelligenceSpike {
    static let shared = IntelligenceSpike()
    private(set) var availability = "Not checked"
    private(set) var available = false
    private(set) var running = false
    private(set) var recipeText: String?
    private(set) var orderText: String?
    private let report = SpikeReport.shared

    func check() {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = "available"; available = true
        case .unavailable(let reason):
            available = false
            switch reason {
            case .deviceNotEligible: availability = "deviceNotEligible (this iPhone can't run Apple Intelligence)"
            case .appleIntelligenceNotEnabled: availability = "appleIntelligenceNotEnabled (turn it on in Settings → Apple Intelligence & Siri)"
            case .modelNotReady: availability = "modelNotReady (still downloading, try later)"
            @unknown default: availability = "unavailable (\(reason))"
            }
        @unknown default:
            availability = "unknown"
        }
        #else
        availability = "FoundationModels not in this SDK"
        #endif
        report.log(.intelligence, "Availability: \(availability)")
        if !available { report.set(.intelligence, .fails, because: availability) }
    }

    func run(vibe: String) async {
        #if canImport(FoundationModels)
        guard available else { check(); return }
        running = true
        defer { running = false }
        let clock = ContinuousClock()
        do {
            let start = clock.now
            let session = LanguageModelSession(instructions: "You turn a listener's description of a vibe into a playlist recipe. Use only the allowed moods.")
            let recipe = try await session.respond(to: vibe, generating: SpikeRecipe.self).content
            let t1 = clock.now - start
            let offList = recipe.moods.filter { !Moods.all.contains($0) }
            recipeText = "\(recipe.name)\n\(recipe.summary)\nmoods \(recipe.moods.joined(separator: ", ")) · genres \(recipe.genres.joined(separator: ", "))\nenergy \(String(format: "%.2f", recipe.energy)) · \(recipe.length) songs"
            report.log(.intelligence, "Recipe in \(t1.formatted(.units(allowed: [.seconds, .milliseconds]))): \(recipe.name) | moods \(recipe.moods) | genres \(recipe.genres) | energy \(recipe.energy) | length \(recipe.length)")
            report.log(.intelligence, offList.isEmpty ? "All moods were from the list" : "Moods NOT on the list: \(offList)")

            let candidates = LibrarySpike.shared.topSongs.prefix(40).enumerated()
                .map { "\($0.offset + 1). \($0.element.title ?? "?") – \($0.element.artist ?? "?")" }
            var t2: Duration = .zero
            if candidates.count >= 10 {
                let start2 = clock.now
                let polish = LanguageModelSession(instructions: "You order songs into a playlist that flows well for a vibe.")
                let order = try await polish.respond(to: "Vibe: \(vibe)\nCandidates:\n\(candidates.joined(separator: "\n"))\nOrder the best 25.",
                                                     generating: SpikeOrder.self).content
                t2 = clock.now - start2
                orderText = "\(order.title): \(order.order.prefix(25).map(String.init).joined(separator: ", "))"
                report.log(.intelligence, "Ordered \(candidates.count) candidates in \(t2.formatted(.units(allowed: [.seconds, .milliseconds]))): \(order.title), \(order.order.count) picks, \(Set(order.order).count) unique")
            } else {
                report.log(.intelligence, "Skipped ordering step (grant library access in spike D for real candidates)")
            }
            let total = t1 + t2
            report.set(.intelligence, total < .seconds(5) ? .works : .partial,
                       because: "Total \(total.formatted(.units(allowed: [.seconds, .milliseconds]))) (target under 5 s)")
        } catch {
            report.log(.intelligence, "Model error: \(error)")
            report.set(.intelligence, .fails, because: error.localizedDescription)
        }
        #endif
    }
}
