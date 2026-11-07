@preconcurrency import MediaPlayer
import SwiftUI

/// The app's view of the Apple Music library: permission, one in-memory snapshot, and sorting/search over it.
/// Reads only — nothing here ever writes to the library (SPEC §9).
@MainActor @Observable
final class LibraryService {
    private(set) var status: MPMediaLibraryAuthorizationStatus
    private(set) var snapshot = LibrarySnapshot()
    /// Ranks and totals for the current snapshot.
    private(set) var stats = LibraryStats()
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private var observing = false
    private var pendingRefresh = false

    init() { status = MPMediaLibrary.authorizationStatus() }

    /// For previews: a fixed snapshot, no MediaPlayer.
    init(preview: LibrarySnapshot) {
        status = .authorized
        snapshot = preview
        stats = LibraryStats(preview)
        hasLoaded = true
    }

    /// Your own hearts (Song/Album Passports) by persistent ID; they win over the Music app's stars.
    private(set) var songHearts: [UInt64: Int] = [:]
    private(set) var albumHearts: [UInt64: Int] = [:]

    func rating(_ s: Song) -> Int { songHearts[s.id] ?? s.rating }
    func rating(_ a: Album) -> Double { albumHearts[a.id].map(Double.init) ?? a.rating }

    /// Re-reads hearts from the passports.
    func reloadPersonalRatings() {
        var songs: [UInt64: Int] = [:]
        for n in Store.shared.allSongNotes() {
            if let r = n.rating, n.itemID.hasPrefix("lib-"), let id = UInt64(n.itemID.dropFirst(4)) { songs[id] = r }
        }
        var albums: [UInt64: Int] = [:]
        for n in Store.shared.allAlbumNotes() {
            if let r = n.rating, n.albumID.hasPrefix("album-"), let id = UInt64(n.albumID.dropFirst(6)) { albums[id] = r }
        }
        songHearts = songs
        albumHearts = albums
    }

    /// Called after every scan (play-count snapshots hook in here).
    @ObservationIgnored var onRefresh: ((LibrarySnapshot) -> Void)?

    var isAuthorized: Bool { status == .authorized }

    func requestAccess() async {
        status = await Self.askForAccess()
        if isAuthorized { await refresh() }
    }

    nonisolated private static func askForAccess() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { @Sendable s in c.resume(returning: s) } }
    }

    /// Re-reads the library. Called on launch, pull to refresh, and when the library changes.
    func refresh() async {
        guard isAuthorized else { return }
        guard !isLoading else { pendingRefresh = true; return }
        isLoading = true
        startObserving()
        let fresh = await LibraryScanner.scan()
        let freshStats = await StatsEngine.build(fresh)
        withAnimation(.liner) {
            snapshot = fresh
            stats = freshStats
        }
        onRefresh?(fresh)
        hasLoaded = true
        isLoading = false
        if pendingRefresh { pendingRefresh = false; await refresh() }
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        NotificationCenter.default.addObserver(forName: .MPMediaLibraryDidChange, object: nil, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { LibraryService.changed() }
        }
    }

    /// The app has one service; the notification reaches it through this hook.
    static var current: LibraryService?
    private static func changed() { if let s = current { Task { await s.refresh() } } }

    // MARK: Sorting

    func artists(_ sort: LibrarySort) -> [Artist] {
        let list = snapshot.artists
        return switch sort {
        case .alphabetical: list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .mostPlayed: list.sorted { $0.playCount > $1.playCount }
        case .recentlyAdded: list.sorted { $0.dateAdded > $1.dateAdded }
        case .rating: list.sorted { ($0.rating, $0.playCount) > ($1.rating, $1.playCount) }
        }
    }

    func albums(_ sort: LibrarySort) -> [Album] {
        let list = snapshot.albums
        return switch sort {
        case .alphabetical: list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .mostPlayed: list.sorted { $0.playCount > $1.playCount }
        case .recentlyAdded: list.sorted { $0.dateAdded > $1.dateAdded }
        case .rating: list.sorted { (rating($0), $0.playCount) > (rating($1), $1.playCount) }
        }
    }

    func songs(_ sort: LibrarySort) -> [Song] {
        let list = snapshot.songs
        return switch sort {
        case .alphabetical: list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .mostPlayed: list.sorted { ($0.playCount, $0.lastPlayed ?? .distantPast) > ($1.playCount, $1.lastPlayed ?? .distantPast) }
        case .recentlyAdded: list.sorted { $0.dateAdded > $1.dateAdded }
        case .rating: list.sorted { (rating($0), $0.playCount) > (rating($1), $1.playCount) }
        }
    }

    func playlists(_ sort: LibrarySort) -> [Playlist] {
        let list = snapshot.playlists
        return switch sort {
        case .alphabetical, .rating: list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .mostPlayed: list.sorted { $0.playCount > $1.playCount }
        case .recentlyAdded: list.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        }
    }

    var recentlyAdded: [Album] { Array(albums(.recentlyAdded).prefix(24)) }

    // MARK: Search

    struct Results {
        var artists: [Artist] = []
        var albums: [Album] = []
        var songs: [Song] = []
        var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }
    }

    func search(_ text: String) -> Results {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Results() }
        func hit(_ s: String) -> Bool { s.localizedStandardContains(q) }
        return Results(
            artists: snapshot.artists.filter { hit($0.name) }.sorted { $0.playCount > $1.playCount }.prefix(8).map { $0 },
            albums: snapshot.albums.filter { hit($0.title) || hit($0.artist) }.sorted { $0.playCount > $1.playCount }.prefix(12).map { $0 },
            songs: snapshot.songs.filter { hit($0.title) || hit($0.artist) }.sorted { $0.playCount > $1.playCount }.prefix(30).map { $0 })
    }
}
