import Foundation

// ┌──────────────────────────────────────────────────────────────────────────────────────────┐
// │ Every change to the app gets an entry here. Add the newest release at the TOP of          │
// │ `Changelog.releases`, bump MARKETING_VERSION in project.yml to match, and give each item   │
// │ a `tour` page (symbol, title, detail and, if it has a screen, an `action` to try it).      │
// │ The What's New tour, the update log in Settings and the version number all read from here. │
// └──────────────────────────────────────────────────────────────────────────────────────────┘

/// Where "Try it" on a tour page takes you.
enum TourAction: String, Hashable {
    case home, diary, library, profile, search, finder, ask, yearReview, scanTicket, stats, friends, settings, randomPick, quickLog

    @MainActor func perform() {
        let r = Router.shared
        switch self {
        case .home: r.tab = .films
        case .diary: r.tab = .diary
        case .library: r.tab = .library
        case .profile: r.tab = .profile
        case .search: r.tab = .search
        case .finder: r.sheet = .finder(nil)
        case .ask: r.sheet = .ask
        case .yearReview: r.sheet = .yearReview(Date.now.year)
        case .scanTicket: r.sheet = .scanTicket
        case .stats: r.tab = .profile; r.profilePath.append(StatsRoute())
        case .friends: r.tab = .profile; r.profilePath.append(FeedRoute())
        case .settings: r.sheet = .settings
        case .randomPick: r.pickRandom(from: Library.shared)
        case .quickLog: r.sheet = .quickLog
        }
    }
}

/// One change, and its page in the tour.
struct ChangeItem: Identifiable, Hashable {
    var symbol: String
    var title: String
    var detail: String
    var action: TourAction? = nil
    var id: String { title }
}

/// A version of Matinee and what changed in it.
struct Release: Identifiable, Hashable {
    var version: String
    var date: String
    var headline: String
    var items: [ChangeItem]
    var id: String { version }
}

enum Changelog {
    /// Newest first.
    static let releases: [Release] = [
        Release(version: "1.5", date: "6 November 2026", headline: "Straight to your story", items: [
            ChangeItem(symbol: "camera.circle.fill", title: "Share to Instagram Stories",
                       detail: "Swipe right on a diary entry and tap Story, or use ••• on any film. Your film becomes a cinema ticket — poster, score, heart and a line of your review — that drops into Instagram's story editor, ready to move about. Pick Glow, Colour or Poster for the look.",
                       action: .diary),
        ]),
        Release(version: "1.4", date: "3 November 2026", headline: "What's on, what's next", items: [
            ChangeItem(symbol: "play.tv.fill", title: "Your streaming services",
                       detail: "Tick the services you pay for in Settings → My streaming services. Your watchlist can then show only what's on them, Home gets a Ready to stream row, and Matinee tells you when a watchlist title arrives on one.",
                       action: .settings),
            ChangeItem(symbol: "calendar", title: "Coming up",
                       detail: "A calendar of new episodes for the shows you follow and release days for films on your watchlist, with the next few on Home.",
                       action: .home),
            ChangeItem(symbol: "photo.on.rectangle.angled", title: "Pick your poster",
                       detail: "On any film or show, ••• → Choose poster… lets you swap in another poster from TMDB. It's used everywhere the title appears, the widget too."),
            ChangeItem(symbol: "eye.trianglebadge.exclamationmark", title: "Spoiler warnings and drafts",
                       detail: "Mark a review as containing spoilers and friends see a warning until they tap. Close the log sheet halfway through a review and it's waiting next time.",
                       action: .diary),
            ChangeItem(symbol: "square.stack.3d.up.fill", title: "Series and Coming soon",
                       detail: "Film pages show the series a film belongs to and how many of it you've seen. Home has a Coming soon shelf of films about to open.",
                       action: .home),
            ChangeItem(symbol: "person.2.wave.2", title: "You vs the crowd",
                       detail: "Stats compares your scores with TMDB members' — on average, and the films where you differ most — and can show any single year.",
                       action: .stats),
            ChangeItem(symbol: "eye.fill", title: "See what you've seen",
                       detail: "Trending, genre and “more like this” shelves mark films you've watched, and can fade them (Settings → Ratings and browsing). Lists can be duplicated."),
        ]),
        Release(version: "1.3", date: "3 November 2026", headline: "Ready for everyone", items: [
            ChangeItem(symbol: "person.badge.key.fill", title: "Sign in your way",
                       detail: "Continue with Apple, Google or email — or GitHub, Discord and more if your account server offers them. Email accounts can be made and reset right in the app, and Settings → Account server sets up your own server.",
                       action: .settings),
            ChangeItem(symbol: "externaldrive.badge.icloud", title: "Backups, and Letterboxd export",
                       detail: "Settings → Backups saves your whole library to Files or iCloud Drive, and restores it without losing anything already here. Export your diary and watchlist as CSVs that letterboxd.com/import reads.",
                       action: .settings),
            ChangeItem(symbol: "target", title: "A goal for the year",
                       detail: "Set how many films you want to watch this year, and your Diary shows how far along you are and whether you're ahead of pace.",
                       action: .diary),
            ChangeItem(symbol: "calendar.badge.clock", title: "On this day",
                       detail: "Home shows what you were watching on today's date in years gone by.",
                       action: .home),
            ChangeItem(symbol: "globe", title: "Where to watch, wherever you are",
                       detail: "Streaming, rental and cinema listings now follow your country instead of India. Change it in Settings → Film data.",
                       action: .settings),
            ChangeItem(symbol: "checklist", title: "Catch up in one tap",
                       detail: "Press and hold an episode for Watched up to here, and every earlier episode in the season is ticked off too.",
                       action: .library),
            ChangeItem(symbol: "arrow.up.arrow.down", title: "Sort your shelves",
                       detail: "Order your watchlist and your films by title, release year or your rating. Diary search now finds words in your reviews as well.",
                       action: .library),
            ChangeItem(symbol: "apps.iphone", title: "Quick actions",
                       detail: "Press and hold the Matinee icon on your Home Screen to log a film, get a random pick, scan a ticket or find what a clip is from."),
            ChangeItem(symbol: "hand.raised.fill", title: "You're in control",
                       detail: "Delete your account from Settings. Block anyone from their profile or a post. Stop sharing your diary and take down what you shared. Paused films can be finished or dropped from Home."),
            ChangeItem(symbol: "wrench.and.screwdriver.fill", title: "Fixes",
                       detail: "Charts, new episodes and air dates refresh properly, and pull to refresh fetches new films. Going offline never signs you out, and signing in on a new phone can't overwrite your library — one made without an account is merged in. Undo only takes back your last change. Letterboxd imports match the right year and never log a film twice. Watch parties don't end on a dropped connection. Reduce Motion skips the opening titles and stills the moving backgrounds."),
        ]),
        Release(version: "1.2.2", date: "28 October 2026", headline: "Layout fixes", items: [
            ChangeItem(symbol: "rectangle.portrait.and.arrow.forward", title: "Everything fits on screen",
                       detail: "Tour pages no longer run off the sides of the screen, and the Stats, Year and Friends buttons on your profile stay on one line.",
                       action: .profile),
        ]),
        Release(version: "1.2.1", date: "27 October 2026", headline: "A sharper finder, and a round of fixes", items: [
            ChangeItem(symbol: "link", title: "The finder follows short links",
                       detail: "vm.tiktok.com, t.co, bit.ly and other short links are opened first, so more posts can be read. When several clues point to the same title it ranks higher, and every guess is checked at once, so results come back faster.",
                       action: .finder),
            ChangeItem(symbol: "person.3.fill", title: "Watch parties stay in step",
                       detail: "Starting or resuming a party film from anywhere — the Home shelf, the Now Watching bar, an episode — now plays it for everyone. Stopping tracking a film leaves its party, and a host stopping ends it."),
            ChangeItem(symbol: "wrench.and.screwdriver.fill", title: "Fixes",
                       detail: "The Lock Screen timer now shows the right episode when you move on to the next one. Signing out clears your friends feed. No more doubled posters behind the sign-in screen."),
        ]),
        Release(version: "1.2", date: "27 October 2026", headline: "Find anything, and everyone who made it", items: [
            ChangeItem(symbol: "sparkle.magnifyingglass", title: "What's this from?",
                       detail: "Paste a YouTube Short, X post, TikTok, Reel or Reddit link — or describe a scene, or pick a screenshot. Matinee reads the post and the text in the video frame, Apple Intelligence works out the film or show on your iPhone, and TMDB confirms it.",
                       action: .finder),
            ChangeItem(symbol: "person.2.crop.square.stack", title: "Everyone who made it",
                       detail: "Film pages now show the crew — writers, producers, composer, cinematographer, editor — next to the cast. Tap anyone to see everything they've worked on, films and shows, grouped by role, with how many you've seen.",
                       action: .search),
            ChangeItem(symbol: "magnifyingglass", title: "Search finds people",
                       detail: "Type an actor's or director's name in Search to jump to their filmography. Paste a link there and it goes straight to the finder.",
                       action: .search),
            ChangeItem(symbol: "list.bullet.rectangle.portrait", title: "Update log and tours",
                       detail: "Settings → What's new lists every version and its changes. New here? Settings → Take the tour any time.",
                       action: .settings),
        ]),
        Release(version: "1.1", date: "27 October 2026", headline: "Your year, your friends, and Apple Intelligence", items: [
            ChangeItem(symbol: "sparkles.rectangle.stack", title: "Year in Review",
                       detail: "Your top films, hours watched, busiest month, genres, director of the year and habits — a card at a time, with a story image to share.",
                       action: .yearReview),
            ChangeItem(symbol: "apple.intelligence", title: "Ask Matinee",
                       detail: "Say what you're in the mood for and Apple Intelligence picks from your watchlist, on your iPhone. In the log sheet, “Write it up” turns quick notes into a review.",
                       action: .ask),
            ChangeItem(symbol: "chart.bar.fill", title: "Stats",
                       detail: "Genres, decades, countries, and the directors and actors you keep coming back to.",
                       action: .stats),
            ChangeItem(symbol: "person.2.fill", title: "Friends, Blend and watch parties",
                       detail: "Follow people and see what they're watching. Blend shows your taste match and films you both want to see. Watch parties keep everyone's timer in step.",
                       action: .friends),
            ChangeItem(symbol: "ticket.fill", title: "Scan a ticket",
                       detail: "Photograph a cinema ticket and Matinee logs the film with the date on it.",
                       action: .scanTicket),
            ChangeItem(symbol: "bell.badge.fill", title: "Reminders",
                       detail: "A notification when the next episode of a show you're watching airs, and when films on your watchlist come out."),
            ChangeItem(symbol: "waveform", title: "Siri and Shortcuts",
                       detail: "“Hey Siri, ask Matinee what to watch”, “Log a film in Matinee”, “What's next on my show in Matinee”. They work on the Action button too."),
            ChangeItem(symbol: "chart.xyaxis.line", title: "Rewatch chart and Spotlight",
                       detail: "See how your score for a film changed across viewings. Your films and watchlist now show up in iPhone search."),
        ]),
        Release(version: "1.0", date: "October 2026", headline: "Matinee", items: [
            ChangeItem(symbol: "film.stack", title: "A film diary for iPhone",
                       detail: "Log films and shows with a date, a score out of 100 (or stars), a review and tags. Liquid Glass and a pure-black OLED theme."),
            ChangeItem(symbol: "dice.fill", title: "Random pick",
                       detail: "Shake your phone for a deck of picks from your watchlist, filtered by how much time you have."),
            ChangeItem(symbol: "tv", title: "TV shows",
                       detail: "Tick off episodes, rate them, pin shows to Currently watching, and wrap up seasons."),
            ChangeItem(symbol: "play.circle", title: "Now watching",
                       detail: "A live timer in the Dynamic Island, with intermissions, moods and notes."),
        ]),
    ]

    /// The version these notes describe; matches MARKETING_VERSION in project.yml.
    static var current: String { releases.first?.version ?? "1.0" }

    /// What the installed app says it is, e.g. "1.2 (3)".
    static var installed: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? current
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    /// Releases after `version`, newest first.
    static func since(_ version: String) -> [Release] {
        releases.filter { compare($0.version, version) == .orderedDescending }
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

/// The welcome tour for new people, and What's New for everyone after an update.
enum TourMode: Identifiable, Hashable {
    case welcome
    case whatsNew([Release])
    var id: String {
        switch self {
        case .welcome: return "welcome"
        case .whatsNew(let r): return "new-" + r.map(\.version).joined(separator: ",")
        }
    }
}

@MainActor
enum Tour {
    static let seenKey = "tourSeenVersion"

    /// Captured at launch, before anything is saved: is this the very first time the app has opened?
    private static var firstLaunch: Bool?

    static func prepare() {
        guard firstLaunch == nil else { return }
        let d = UserDefaults.standard
        let usedBefore = d.object(forKey: "guest") != nil || d.object(forKey: "tasteProfile") != nil
            || d.object(forKey: "tmdbToken") != nil || !Library.shared.doc.entries.isEmpty || !Library.shared.doc.watchlist.isEmpty
            || Auth.shared.signedIn
        firstLaunch = d.string(forKey: seenKey) == nil && !usedBefore
    }

    /// The tour that's due, if any.
    static var pending: TourMode? {
        prepare()
        let env = ProcessInfo.processInfo.environment
        if env["MATINEE_ONBOARDING"] != nil { return .welcome }
        if env["MATINEE_PREVIEW"] != nil { return nil }
        guard let seen = UserDefaults.standard.string(forKey: seenKey) else {
            // People who used Matinee before tours existed get What's New since 1.0.
            return firstLaunch == true ? .welcome : nonEmpty(Changelog.since("1.0"))
        }
        return nonEmpty(Changelog.since(seen))
    }

    private static func nonEmpty(_ r: [Release]) -> TourMode? { r.isEmpty ? nil : .whatsNew(r) }

    static func markSeen() { UserDefaults.standard.set(Changelog.current, forKey: seenKey) }

    /// The app tour: one page per part of Matinee.
    static let welcomePages: [ChangeItem] = [
        ChangeItem(symbol: "film.stack.fill", title: "Welcome to Matinee",
                   detail: "A film and TV diary for your iPhone. Here's a quick look around — swipe through, or skip any time."),
        ChangeItem(symbol: "house.fill", title: "Home",
                   detail: "What's trending, films and shows picked for your taste, what your friends are watching, the shows you're in the middle of, and what's coming up next.",
                   action: .home),
        ChangeItem(symbol: "star.circle.fill", title: "Every film page",
                   detail: "Watch, like, save and score a film right on its page — drag round the dial or slide across the stars. Tap the poster for the trailer, and see where it's streaming, your own services first.",
                   action: .search),
        ChangeItem(symbol: "book.pages.fill", title: "Your diary",
                   detail: "Log what you watch with the date, your score, a review and tags. Swipe an entry to edit or log it again, scan a cinema ticket to log it in one go, and set a goal for the year.",
                   action: .diary),
        ChangeItem(symbol: "dice.fill", title: "Can't decide?",
                   detail: "Shake your phone (or double-tap Library) for a deck of picks from your watchlist. Swipe left for another, right to open it.",
                   action: .randomPick),
        ChangeItem(symbol: "tv.fill", title: "Shows, episode by episode",
                   detail: "Tick off episodes, rate them, and pin shows to Currently watching. Matinee tells you when the next one airs.",
                   action: .library),
        ChangeItem(symbol: "apple.intelligence", title: "Apple Intelligence, on your iPhone",
                   detail: "Ask Matinee what to watch for your mood, find the film from a TikTok or Short, and turn quick notes into a review. Nothing leaves your phone.",
                   action: .finder),
        ChangeItem(symbol: "person.2.fill", title: "Friends",
                   detail: "Follow people, see what they're watching, Blend your tastes and start a watch party.",
                   action: .friends),
        ChangeItem(symbol: "person.crop.circle.fill", title: "Your profile",
                   detail: "Favourites, your ratings spread, your film character, Stats and your Year in Review.",
                   action: .profile),
        ChangeItem(symbol: "waveform", title: "Just ask Siri",
                   detail: "“Hey Siri, ask Matinee what to watch.” “Log a film in Matinee.” “What's next on my show in Matinee.” Or press and hold the app icon for quick actions."),
        ChangeItem(symbol: "externaldrive.badge.icloud", title: "Your films stay yours",
                   detail: "Sign in to sync, or keep everything on this iPhone. Back up to Files any time, or take your diary to Letterboxd as a CSV.",
                   action: .settings),
    ]
}
