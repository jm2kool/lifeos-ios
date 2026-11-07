@preconcurrency import MediaPlayer
import SwiftData
import SwiftUI

/// Makes, refreshes and saves mood playlists.
@MainActor
enum MoodPlaylistService {
    static func input(_ library: LibraryService, preset: MoodPreset? = nil) -> MoodScorer.Input {
        var moods: [UInt64: [String]] = [:]
        for n in Store.shared.allSongNotes() where !n.moods.isEmpty && n.itemID.hasPrefix("lib-") {
            if let id = UInt64(n.itemID.dropFirst(4)) { moods[id] = n.moods }
        }
        return MoodScorer.Input(songs: library.snapshot.songs, moods: moods, hearts: library.songHearts, preset: preset?.rawValue)
    }

    /// Recipe → scored songs → (optionally) ordered by the model → saved.
    static func make(_ recipe: MoodRecipe, prompt: String, preset: MoodPreset?, polish: Bool, library: LibraryService) async -> MoodPlaylist? {
        var songs = await MoodScorer.pick(recipe, from: input(library, preset: preset))
        guard !songs.isEmpty else { return nil }
        var name = recipe.name
        if polish, MoodAI.state == .available, let p = await MoodAI.polish(songs, vibe: prompt.isEmpty ? recipe.summary : prompt) {
            let ordered = p.order.compactMap { songs.indices.contains($0) ? songs[$0] : nil }
            let rest = songs.filter { s in !ordered.contains(s) }
            songs = MoodScorer.diversify(ordered + rest, length: songs.count)
            if !p.title.isEmpty { name = p.title }
        }
        let playlist = MoodPlaylist(name: name, summary: recipe.summary, prompt: preset?.rawValue ?? prompt,
                                    recipeData: Coding.encode(recipe), trackIDs: songs.map { "lib-\($0.id)" })
        Store.shared.context.insert(playlist)
        Store.shared.save()
        return playlist
    }

    static func refresh(_ p: MoodPlaylist, library: LibraryService) async {
        guard let recipe = Coding.decode(MoodRecipe.self, p.recipeData) else { return }
        let preset = MoodPreset(rawValue: p.prompt)
        let songs = await MoodScorer.pick(recipe, from: input(library, preset: preset))
        guard !songs.isEmpty else { return }
        p.trackIDs = songs.map { "lib-\($0.id)" }
        p.refreshedAt = .now
        Store.shared.save()
    }

    /// Weekly auto-refresh, run at launch.
    static func refreshDue(library: LibraryService) async {
        let all = (try? Store.shared.context.fetch(FetchDescriptor<MoodPlaylist>(predicate: #Predicate { $0.autoRefresh }))) ?? []
        for p in all where Date.now.timeIntervalSince(p.refreshedAt) > 7 * 86_400 { await refresh(p, library: library) }
    }

    static func songs(_ p: MoodPlaylist, library: LibraryService) -> [Song] {
        p.trackIDs.compactMap { id in UInt64(id.dropFirst(4)).flatMap { library.snapshot.songs([$0]).first } }
    }

    /// The one explicit write to the Music library (SPEC §9): a real playlist with these songs.
    static func saveToAppleMusic(_ p: MoodPlaylist, library: LibraryService) async -> String {
        let items = songs(p, library: library).compactMap { library.snapshot.items[$0.id] }
        guard !items.isEmpty else { return "No songs to save." }
        let meta = MPMediaPlaylistCreationMetadata(name: p.name)
        meta.descriptionText = p.summary.isEmpty ? "Made with \(AppBrand.name)" : p.summary
        do {
            let playlist: MPMediaPlaylist = try await withCheckedThrowingContinuation { c in
                MPMediaLibrary.default().getPlaylist(with: p.id, creationMetadata: meta) { @Sendable list, error in
                    if let list { nonisolated(unsafe) let l = list; c.resume(returning: l) } else { c.resume(throwing: error ?? CancellationError()) }
                }
            }
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                playlist.add(items) { @Sendable error in if let error { c.resume(throwing: error) } else { c.resume() } }
            }
            return "Saved “\(p.name)” to your Apple Music library."
        } catch {
            return "Couldn't save the playlist: \(error.localizedDescription)"
        }
    }
}
