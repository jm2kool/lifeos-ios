import SwiftUI

/// Notices albums you've newly listened to and asks for a rating when you open the app.
/// "Listened" means at least half its songs have been played since LINER. started watching (or it has
/// as many plays as half its songs). Albums you'd already played before installing aren't asked about,
/// and an album is only ever asked about once.
@MainActor @Observable
final class NewAlbumPrompts {
    static let shared = NewAlbumPrompts()
    var current: Album?

    @ObservationIgnored private var pending: [UInt64] = []
    private let defaults = UserDefaults.standard

    private var known: Set<UInt64> {
        get { Set((defaults.array(forKey: "albums.known") as? [String] ?? []).compactMap(UInt64.init)) }
        set { defaults.set(newValue.map(String.init), forKey: "albums.known") }
    }
    private var asked: Set<UInt64> {
        get { Set((defaults.array(forKey: "albums.asked") as? [String] ?? []).compactMap(UInt64.init)) }
        set { defaults.set(newValue.map(String.init), forKey: "albums.asked") }
    }

    /// After each scan: find newly listened albums. The very first scan only records what you already know.
    func check(_ snapshot: LibrarySnapshot) {
        guard !snapshot.albums.isEmpty else { return }
        let firstRun = defaults.object(forKey: "albums.known") == nil
        var known = self.known
        let asked = self.asked
        var fresh: [UInt64] = []
        for album in snapshot.albums where album.playCount > 0 && !known.contains(album.id) {
            if firstRun { known.insert(album.id); continue }
            let songs = snapshot.songs(album.songIDs)
            let played = songs.filter { $0.playCount > 0 }.count
            let half = max(1, (songs.count + 1) / 2)
            guard played >= half || album.playCount >= max(3, half) else { continue }
            known.insert(album.id)
            if !asked.contains(album.id), Store.shared.albumNote("album-\(album.id)")?.rating == nil { fresh.append(album.id) }
        }
        self.known = known
        pending.append(contentsOf: fresh.filter { !pending.contains($0) })
        guard !pending.isEmpty else { return }
        // Let the opening animation finish first.
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            showNext(snapshot)
        }
    }

    func showNext(_ snapshot: LibrarySnapshot) {
        guard current == nil else { return }
        while let id = pending.first {
            pending.removeFirst()
            if let album = snapshot.album(id) { current = album; return }
        }
    }

    /// Rated or waved away: never ask about this album again.
    func finish(_ album: Album) {
        var a = asked
        a.insert(album.id)
        asked = a
    }
}

/// "You've been listening to …": a quick rating sheet. Tap outside, swipe down or "Not now" to skip.
struct AlbumRatingPrompt: View {
    let album: Album
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryService.self) private var library
    @State private var rating: Int?

    var body: some View {
        VStack(spacing: 18) {
            Text("New in your rotation").linerLabel(size: 10).padding(.top, 24)
            AlbumHeaderArt(albumID: album.id, note: nil, edition: nil)
                .frame(width: 170, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            VStack(spacing: 4) {
                Text(album.title).font(.serif(26)).multilineTextAlignment(.center).lineLimit(2)
                Text(album.artist).linerLabel(size: 11)
            }
            Text("How would you rate it?").font(.callout).foregroundStyle(Palette.secondary)
            HeartRating(rating: $rating, size: 34)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    GlassPillButton(title: "Not now", systemImage: "xmark") { dismiss() }
                    GlassPillButton(title: "Save rating", systemImage: "heart.fill", prominent: true) { save() }
                        .disabled(rating == nil)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onDisappear { NewAlbumPrompts.shared.finish(album) }
    }

    private func save() {
        let note = Store.shared.albumNoteOrNew("album-\(album.id)", key: album.key)
        note.rating = rating
        Store.shared.save()
        library.reloadPersonalRatings()
        dismiss()
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) { AlbumRatingPrompt(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
