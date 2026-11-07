import SwiftData
import SwiftUI

/// The player's ♥: tap to love (5 hearts) or clear; hold for a 1–5 rating.
struct HeartButton: View {
    let item: QueueItem
    @Query private var notes: [SongNote]
    @Environment(LibraryService.self) private var library

    init(item: QueueItem) {
        self.item = item
        let id = item.id
        _notes = Query(filter: #Predicate<SongNote> { $0.itemID == id })
    }

    private var rating: Int? { notes.first?.rating }

    var body: some View {
        Menu {
            ForEach((1...5).reversed(), id: \.self) { n in
                Button(String(repeating: "♥", count: n)) { set(n) }
            }
            if rating != nil { Button("Clear rating", systemImage: "heart.slash", role: .destructive) { set(nil) } }
        } label: {
            Image(systemName: rating == nil ? "heart" : "heart.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
        } primaryAction: {
            set(rating == nil ? 5 : nil)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .sensoryFeedback(.impact(weight: .medium), trigger: rating)
        .accessibilityLabel(rating.map { "Rated \($0) hearts" } ?? "Love")
    }

    private func set(_ value: Int?) {
        let note = Store.shared.songNoteOrNew(for: item)
        note.rating = value
        note.updatedAt = .now
        Store.shared.dropIfEmpty(note)
        library.reloadPersonalRatings()
    }
}

/// The album page's Passport button.
struct AlbumPassportButton: View {
    let album: Album
    @Environment(PassportPresenter.self) private var passports
    @Environment(LibraryService.self) private var library

    var body: some View {
        GlassCircleButton(systemImage: "text.book.closed", label: "Album Passport", size: 54) {
            passports.album = .library(album, snapshot: library.snapshot)
        }
    }
}
