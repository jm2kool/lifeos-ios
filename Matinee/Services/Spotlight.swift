import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import UIKit

/// Your films, shows and watchlist in iPhone search: type a title on the Home Screen and it opens in Matinee.
@MainActor
enum Spotlight {
    static let domain = "com.jm2kool.matinee.library"
    private static var task: Task<Void, Never>?
    private static var lastSignature = ""

    /// Re-index a few seconds after the library settles.
    static func schedule(_ library: Library) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await index(library)
        }
    }

    static func index(_ library: Library) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        var items: [String: (FilmRef, String)] = [:]
        for f in library.doc.watchlist { items[f.id] = (f, f.isShow ? "Show on your watchlist" : "On your watchlist") }
        for f in library.showsInProgress { items[f.id] = (f, "Show you're watching") }
        for f in library.watchedFilms {
            let score = library.rating(f.id).map { " · " + (FilmRatingStyle.current == .stars ? Stars.text(Score.starsShown($0)) : "\(Score.text($0))/100") } ?? ""
            items[f.id] = (f, (f.isShow ? "Show you've watched" : "Watched") + score + (library.isLiked(f.id) ? " · ♥" : ""))
        }
        let signature = items.map { "\($0.key)|\($0.value.1)" }.sorted().joined(separator: ",")
        guard signature != lastSignature else { return }
        lastSignature = signature

        let searchable: [CSSearchableItem] = items.values.map { film, line in
            let a = CSSearchableItemAttributeSet(contentType: UTType.content)
            a.title = film.title + (film.year.map { " (\($0))" } ?? "")
            a.displayName = film.title
            a.contentDescription = line
            a.keywords = [film.title, film.isShow ? "show" : "film", "matinee"] + (film.year.map { [String($0)] } ?? [])
            if let p = film.poster, let img = ImageStore.shared.cached(p) {
                a.thumbnailData = img.preparingThumbnail(of: CGSize(width: 120, height: 180))?.jpegData(compressionQuality: 0.7)
            }
            let item = CSSearchableItem(uniqueIdentifier: film.id, domainIdentifier: domain, attributeSet: a)
            item.expirationDate = .distantFuture
            return item
        }
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        try? await index.indexSearchableItems(searchable)
    }

    /// The film a Spotlight result points at.
    static func film(for activity: NSUserActivity, in library: Library) -> FilmRef? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return library.doc.watchlist.first { $0.id == id } ?? library.watchedFilms.first { $0.id == id }
            ?? library.showsInProgress.first { $0.id == id } ?? FilmRef(id: id, title: "")
    }
}
