import AppIntents
import Foundation

// Siri, Shortcuts, Spotlight and the Action button. Each phrase has to name the app.

struct RandomPickIntent: AppIntent {
    static var title: LocalizedStringResource = "Random Pick from Watchlist"
    static var description = IntentDescription("Shuffle your watchlist into a deck of picks for tonight.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.pickRandom(from: Library.shared)
        return .result()
    }
}

struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Something I Watched"
    static var description = IntentDescription("Open Matinee ready to search for a film or show and log it.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.sheet = .quickLog
        return .result()
    }
}

/// "Log Dune in Matinee" — finds the film and adds it to your diary without opening the app.
struct LogFilmIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Film"
    static var description = IntentDescription("Add a film or show to your diary for today, with an optional score out of 100.")

    @Parameter(title: "Title", requestValueDialog: "What did you watch?")
    var name: String

    @Parameter(title: "Score out of 100")
    var score: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard Catalog.hasToken else { return .result(dialog: "Connect TMDB in Matinee first, so I can find films.") }
        guard let film = (try? await Catalog.search(name))?.first else {
            return .result(dialog: "I couldn't find \(name). Try the original title?")
        }
        let comfort = Library.shared.isComfort(film.id)
        var e = LogEntry(film: film)
        e.rating = comfort ? nil : score.map { Double(min(100, max(1, $0))) }
        e.rewatch = Library.shared.isWatched(film.id)
        Library.shared.log(e)
        let year = film.year.map { " (\($0))" } ?? ""
        if let s = e.rating { return .result(dialog: "Logged \(film.title)\(year) with \(Int(s)) out of 100.") }
        return .result(dialog: "Logged \(film.title)\(year) for today.")
    }
}

/// "What's next on my show" — the next episode of the show you pinned first.
struct NextEpisodeIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next on My Show"
    static var description = IntentDescription("Hear the next episode of the show at the top of Currently watching.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let lib = Library.shared
        guard let show = lib.currentlyWatching.first ?? lib.showsInProgress.first else {
            return .result(dialog: "You're not watching any shows right now. Pin one from its page in Matinee.")
        }
        guard let d = try? await Catalog.detail(show.id) else { return .result(dialog: "I couldn't reach TMDB to check \(show.title).") }
        for s in d.regularSeasons where lib.seenCount(show.id, season: s.number) < s.episodeCount {
            guard let eps = try? await Catalog.season(show.id, s.number) else { break }
            if let e = eps.first(where: { $0.aired && !lib.isSeen(show.id, $0) }) {
                return .result(dialog: "Next on \(show.title) is season \(e.season), episode \(e.number): \(e.name).")
            }
            if eps.contains(where: { !$0.aired }) { break }
        }
        if let n = d.nextEpisode, let day = n.airDate {
            return .result(dialog: "You're all caught up on \(show.title). The next episode, \(n.name), airs \(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).")
        }
        return .result(dialog: "You're all caught up on \(show.title).")
    }
}

/// "Ask Matinee what to watch" — Apple Intelligence picks from your watchlist to suit your mood.
struct AskMatineeIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Matinee What to Watch"
    static var description = IntentDescription("Say what you're in the mood for and get a pick from your watchlist, chosen on your iPhone.")

    @Parameter(title: "Mood", requestValueDialog: "What are you in the mood for?")
    var mood: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let list = Library.shared.doc.watchlist
        guard !list.isEmpty else { return .result(dialog: "Your watchlist is empty. Save a few films in Matinee first.") }
        let picks = await Intelligence.pick(mood: mood, from: list.shuffled())
        guard let first = picks.first else { return .result(dialog: "I couldn't find a match on your watchlist.") }
        let year = first.film.year.map { " from \($0)" } ?? ""
        var text = "Try \(first.film.title)\(year). \(first.reason)"
        if picks.count > 1 { text += " Or \(picks.dropFirst().map(\.film.title).joined(separator: " or "))." }
        return .result(dialog: "\(text)")
    }
}

struct YearInReviewIntent: AppIntent {
    static var title: LocalizedStringResource = "Show My Year in Review"
    static var description = IntentDescription("Your year in films and shows.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.sheet = .yearReview(Date.now.year)
        return .result()
    }
}

struct ScanTicketIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan a Cinema Ticket"
    static var description = IntentDescription("Photograph a ticket and log the film with the date on it.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.sheet = .scanTicket
        return .result()
    }
}

struct MatineeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskMatineeIntent(), phrases: [
            "Ask \(.applicationName) what to watch",
            "What should I watch in \(.applicationName)",
            "Help me pick a film in \(.applicationName)",
        ], shortTitle: "Ask Matinee", systemImageName: "sparkles")
        AppShortcut(intent: RandomPickIntent(), phrases: [
            "Pick a film in \(.applicationName)",
            "Random pick in \(.applicationName)",
            "Shuffle my \(.applicationName) watchlist",
        ], shortTitle: "Random pick", systemImageName: "dice")
        AppShortcut(intent: LogFilmIntent(), phrases: [
            "Log a film in \(.applicationName)",
            "Add to my \(.applicationName) diary",
        ], shortTitle: "Log a film", systemImageName: "plus.circle")
        AppShortcut(intent: NextEpisodeIntent(), phrases: [
            "What's next on my show in \(.applicationName)",
            "Next episode in \(.applicationName)",
        ], shortTitle: "Next episode", systemImageName: "tv")
        AppShortcut(intent: QuickLogIntent(), phrases: [
            "Open \(.applicationName) to log",
        ], shortTitle: "Quick log", systemImageName: "square.and.pencil")
        AppShortcut(intent: YearInReviewIntent(), phrases: [
            "Show my year in \(.applicationName)",
            "My \(.applicationName) year in review",
        ], shortTitle: "Year in review", systemImageName: "calendar")
        AppShortcut(intent: ScanTicketIntent(), phrases: [
            "Scan a ticket in \(.applicationName)",
        ], shortTitle: "Scan ticket", systemImageName: "ticket")
    }
}
