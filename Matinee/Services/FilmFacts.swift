import Foundation

/// The few things about a film that stats need — genres, who made it, who's in it, how long it runs —
/// kept on the phone so the Stats page and Year in Review don't have to ask TMDB about every film each time.
struct FilmFacts: Codable, Hashable {
    var genres: [String] = []
    var directors: [Person] = []
    var cast: [Person] = []          // top billed, up to eight
    var countries: [String] = []
    var runtime: Int?                // minutes; for a show, a typical episode
    var year: Int?

    init(_ d: FilmDetail) {
        genres = d.genres
        directors = d.directorPeople
        cast = Array(d.cast.prefix(8))
        countries = d.countries
        runtime = d.runtimeMinutes
        year = d.ref.year
    }
}

@Observable @MainActor
final class FactStore {
    static let shared = FactStore()

    private(set) var facts: [String: FilmFacts] = [:]
    /// While filling in films that have no facts yet: how many are done out of how many.
    private(set) var filling: (done: Int, total: Int)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Matinee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("facts.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode([String: FilmFacts].self, from: data) { facts = f }
    }

    subscript(_ id: String) -> FilmFacts? { facts[id] }

    /// Called whenever a film's page loads, so facts build up as you browse.
    func record(_ d: FilmDetail) {
        let f = FilmFacts(d)
        guard facts[d.ref.id] != f else { return }
        facts[d.ref.id] = f
        saveSoon()
    }

    /// Look up the films that have no facts yet, a few at a time. Returns once they're all in (or failed).
    func fill(_ films: [FilmRef], limit: Int = 500) async {
        let missing = Array(films.filter { facts[$0.id] == nil && TMDB.path($0.id) != nil }.prefix(limit))
        guard !missing.isEmpty, filling == nil, Catalog.hasToken else { return }
        filling = (0, missing.count)
        defer { filling = nil }
        for start in stride(from: 0, to: missing.count, by: 6) {
            let chunk = missing[start..<min(start + 6, missing.count)]
            await withTaskGroup(of: Void.self) { g in
                for f in chunk { g.addTask { _ = try? await Catalog.detail(f.id) } }
            }
            filling = (min(start + 6, missing.count), missing.count)
            if Task.isCancelled { break }
        }
    }

    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(facts) else { return }
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
