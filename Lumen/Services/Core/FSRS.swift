import Foundation

/// The four answers in a review.
enum Rating: Int, CaseIterable, Identifiable, Codable {
    case again = 1, hard, good, easy
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

/// FSRS-4.5 spaced repetition (the open scheduler Anki uses), with its published default weights.
/// A card's memory is described by stability (days until recall drops to 90%) and difficulty (1–10).
/// Again brings a card back in a minute so you see it again this session; the other answers schedule it in days.
struct FSRS {
    struct Memory: Equatable {
        var state: String = "new"          // new | learning | review | relearning
        var stability: Double = 0
        var difficulty: Double = 0
        var reps: Int = 0
        var lapses: Int = 0
        var scheduledDays: Double = 0
        var lastReview: Date?
        var due: Date = .distantPast
    }

    static let defaultWeights: [Double] = [0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, 0.1367,
                                           1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755]
    static let decay = -0.5
    static let factor = 19.0 / 81.0      // so that retrievability is 90% when elapsed time equals stability

    var w: [Double] = FSRS.defaultWeights
    var retention: Double = 0.9
    var maxInterval: Double = 36500

    init(retention: Double = 0.9) { self.retention = min(0.97, max(0.7, retention)) }

    /// How likely you are to remember after `elapsed` days.
    static func retrievability(elapsed: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * max(0, elapsed) / stability, decay)
    }

    func interval(for stability: Double) -> Double {
        let raw = stability / FSRS.factor * (pow(retention, 1 / FSRS.decay) - 1)
        return min(maxInterval, max(1, raw.rounded()))
    }

    private func initialStability(_ r: Rating) -> Double { max(0.1, w[r.rawValue - 1]) }
    private func initialDifficulty(_ r: Rating) -> Double { clampD(w[4] - Double(r.rawValue - 3) * w[5]) }
    private func clampD(_ d: Double) -> Double { min(10, max(1, d)) }

    private func nextDifficulty(_ d: Double, _ r: Rating) -> Double {
        let next = d - w[6] * Double(r.rawValue - 3)
        return clampD(w[7] * initialDifficulty(.good) + (1 - w[7]) * next)
    }

    private func recallStability(_ d: Double, _ s: Double, _ r: Double, _ rating: Rating) -> Double {
        let hard = rating == .hard ? w[15] : 1
        let easy = rating == .easy ? w[16] : 1
        return s * (exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy + 1)
    }

    private func forgetStability(_ d: Double, _ s: Double, _ r: Double) -> Double {
        min(s, w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r)))
    }

    /// The card's memory after answering `rating` at `now`.
    func review(_ m: Memory, _ rating: Rating, now: Date = Date()) -> Memory {
        var out = m
        out.reps += 1
        out.lastReview = now
        if m.state == "new" || m.stability <= 0 {
            out.stability = initialStability(rating)
            out.difficulty = initialDifficulty(rating)
        } else {
            let elapsed = m.lastReview.map { max(0, now.timeIntervalSince($0) / 86400) } ?? 0
            let r = FSRS.retrievability(elapsed: elapsed, stability: m.stability)
            out.difficulty = nextDifficulty(m.difficulty, rating)
            if rating == .again {
                out.stability = max(0.1, forgetStability(m.difficulty, m.stability, r))
            } else if elapsed < 1 && (m.state == "learning" || m.state == "relearning") {
                // A second look the same day: a short-term bump rather than the full long-term update.
                out.stability = max(m.stability, m.stability * exp(w[8] * 0.2 * Double(rating.rawValue - 2)))
            } else {
                out.stability = recallStability(m.difficulty, m.stability, r, rating)
            }
        }

        if rating == .again {
            if m.state == "review" { out.lapses += 1 }
            out.state = (m.state == "new" || m.state == "learning") ? "learning" : "relearning"
            out.scheduledDays = 0
            out.due = now.addingTimeInterval(60)
            return out
        }

        // Hard ≤ Good ≤ Easy, each at least a day apart, as FSRS does.
        let hardS = rating == .hard ? out.stability : stabilityIf(m, .hard, now: now)
        let goodS = rating == .good ? out.stability : stabilityIf(m, .good, now: now)
        var hardI = interval(for: hardS)
        var goodI = interval(for: goodS)
        hardI = min(hardI, goodI)
        goodI = max(goodI, hardI + 1)
        var days: Double
        switch rating {
        case .hard: days = hardI
        case .good: days = goodI
        case .easy: days = max(interval(for: out.stability), goodI + 1)
        case .again: days = 0
        }
        days = min(maxInterval, days)
        out.state = "review"
        out.scheduledDays = days
        out.due = now.addingTimeInterval(days * 86400)
        return out
    }

    private func stabilityIf(_ m: Memory, _ rating: Rating, now: Date) -> Double {
        if m.state == "new" || m.stability <= 0 { return initialStability(rating) }
        let elapsed = m.lastReview.map { max(0, now.timeIntervalSince($0) / 86400) } ?? 0
        let r = FSRS.retrievability(elapsed: elapsed, stability: m.stability)
        if elapsed < 1 && (m.state == "learning" || m.state == "relearning") {
            return max(m.stability, m.stability * exp(w[8] * 0.2 * Double(rating.rawValue - 2)))
        }
        return recallStability(m.difficulty, m.stability, r, rating)
    }

    /// What each button would do, for the labels under them ("1m", "2d", "5d", "12d").
    func preview(_ m: Memory, now: Date = Date()) -> [Rating: Memory] {
        var out: [Rating: Memory] = [:]
        for r in Rating.allCases { out[r] = review(m, r, now: now) }
        return out
    }

    static func shortInterval(_ seconds: TimeInterval) -> String {
        let m = seconds / 60
        if m < 60 { return "\(max(1, Int(m.rounded())))m" }
        let h = m / 60
        if h < 24 { return "\(Int(h.rounded()))h" }
        let d = h / 24
        if d < 30 { return "\(Int(d.rounded()))d" }
        if d < 365 { return "\(Int((d / 30).rounded()))mo" }
        return String(format: "%.1fy", d / 365)
    }
}
