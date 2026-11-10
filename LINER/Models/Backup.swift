import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Export / import of everything you wrote in LINER. (SPEC §6.17) as one JSON file: passports, rankings, pins,
/// editions, mixtape details (not the audio files), mood playlists, your album groups, vinyl sides, the Listening
/// Room shelf and your artist posters.
struct BackupFile: Codable {
    struct Song: Codable { var itemID: String; var key: Data; var rating: Int?; var moods: [String]; var notes: String; var connection: String; var moments: Data; var lyricLines: [String] }
    struct Album: Codable { var albumID: String; var key: Data; var rating: Int?; var ranking: [String]; var pinned: Bool; var appearance: String; var cover: Data?; var activeEdition: UUID? }
    struct EditionItem: Codable { var id: UUID; var base: String?; var title: String; var tracks: Data; var cover: Data?; var isActive: Bool; var createdAt: Date }
    struct Track: Codable { var id: UUID; var title: String; var artist: String; var fileName: String; var duration: Double; var number: Int; var lrc: String? }
    struct MixtapeItem: Codable { var id: UUID; var title: String; var artist: String; var label: String?; var year: Int?; var cover: Data?; var showInHome: Bool; var tracks: [Track] }
    struct Mood: Codable { var id: UUID; var name: String; var summary: String; var prompt: String; var recipe: Data; var tracks: [String]; var autoRefresh: Bool }

    var version = 1
    var exportedAt = Date.now
    var songs: [Song] = []
    var albums: [Album] = []
    var editions: [EditionItem] = []
    var mixtapes: [MixtapeItem] = []
    var moods: [Mood] = []
    var pinnedPlaylists: [Int64] = []
    // Added in 1.5 (older backups don't have them).
    var albumGroups: [[String]]?
    var albumSplits: [String]?
    var vinylSides: [String: [[String]]]?
    var roomShelf: [String]?
    var artistPosters: [String: Data]?
}

@MainActor
enum BackupService {
    static func export() throws -> URL {
        let c = Store.shared.context
        var b = BackupFile()
        b.songs = ((try? c.fetch(FetchDescriptor<SongNote>())) ?? []).map {
            .init(itemID: $0.itemID, key: $0.keyData, rating: $0.rating, moods: $0.moods, notes: $0.notes, connection: $0.connection, moments: $0.momentsData, lyricLines: $0.lyricLines)
        }
        b.albums = ((try? c.fetch(FetchDescriptor<AlbumNote>())) ?? []).map {
            .init(albumID: $0.albumID, key: $0.keyData, rating: $0.rating, ranking: $0.personalRanking, pinned: $0.pinned,
                  appearance: $0.pinnedAppearanceRaw, cover: $0.coverOverride, activeEdition: $0.activeEditionID)
        }
        b.editions = ((try? c.fetch(FetchDescriptor<Edition>())) ?? []).map {
            .init(id: $0.id, base: $0.baseAlbumID, title: $0.title, tracks: $0.tracksData, cover: $0.coverImage, isActive: $0.isActive, createdAt: $0.createdAt)
        }
        b.mixtapes = ((try? c.fetch(FetchDescriptor<Mixtape>())) ?? []).map { m in
            .init(id: m.id, title: m.title, artist: m.artist, label: m.label, year: m.year, cover: m.coverImage, showInHome: m.showInHome,
                  tracks: m.orderedTracks.map { .init(id: $0.id, title: $0.title, artist: $0.artist, fileName: $0.fileName, duration: $0.duration, number: $0.trackNumber, lrc: $0.lyricsLRC) })
        }
        b.moods = ((try? c.fetch(FetchDescriptor<MoodPlaylist>())) ?? []).map {
            .init(id: $0.id, name: $0.name, summary: $0.summary, prompt: $0.prompt, recipe: $0.recipeData, tracks: $0.trackIDs, autoRefresh: $0.autoRefresh)
        }
        b.pinnedPlaylists = ((try? c.fetch(FetchDescriptor<PinnedPlaylist>())) ?? []).map(\.playlistID)
        let groups = AlbumGroups.stored
        b.albumGroups = groups.groups
        b.albumSplits = groups.split
        b.vinylSides = VinylSides.shared.layouts
        b.roomShelf = RoomShelf.shared.ids
        b.artistPosters = ArtistPosters.shared.all()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let url = URL.temporaryDirectory.appending(path: "LINER-backup-\(Date.now.formatted(.iso8601.year().month().day())).json")
        try enc.encode(b).write(to: url, options: .atomic)
        return url
    }

    /// Merges a backup in: items with the same ID are updated, others added. Returns a summary.
    static func restore(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let b = try dec.decode(BackupFile.self, from: Data(contentsOf: url))
        let c = Store.shared.context
        for s in b.songs {
            let n = Store.shared.songNote(s.itemID) ?? { let fresh = SongNote(itemID: s.itemID, key: nil); c.insert(fresh); return fresh }()
            n.keyData = s.key; n.rating = s.rating; n.moods = s.moods; n.notes = s.notes; n.connection = s.connection
            n.momentsData = s.moments; n.lyricLines = s.lyricLines
        }
        for a in b.albums {
            let n = Store.shared.albumNoteOrNew(a.albumID, key: nil)
            n.keyData = a.key; n.rating = a.rating; n.personalRanking = a.ranking; n.pinned = a.pinned
            n.pinnedAt = a.pinned ? (n.pinnedAt ?? .now) : nil; n.pinnedAppearanceRaw = a.appearance
            n.coverOverride = a.cover ?? n.coverOverride; n.activeEditionID = a.activeEdition
        }
        let editions = (try? c.fetch(FetchDescriptor<Edition>())) ?? []
        for e in b.editions where !editions.contains(where: { $0.id == e.id }) {
            let ed = Edition(title: e.title, baseAlbumID: e.base, tracks: [])
            ed.id = e.id; ed.tracksData = e.tracks; ed.coverImage = e.cover; ed.isActive = e.isActive; ed.createdAt = e.createdAt
            c.insert(ed)
        }
        let mixtapes = (try? c.fetch(FetchDescriptor<Mixtape>())) ?? []
        var missingAudio = 0
        for m in b.mixtapes where !mixtapes.contains(where: { $0.id == m.id }) {
            let mx = Mixtape(title: m.title, artist: m.artist)
            mx.id = m.id; mx.label = m.label; mx.year = m.year; mx.coverImage = m.cover; mx.showInHome = m.showInHome
            c.insert(mx)
            for t in m.tracks {
                if !FileManager.default.fileExists(atPath: MixtapeFiles.url(t.fileName).path) { missingAudio += 1 }
                let tr = MixtapeTrack(title: t.title, artist: t.artist, fileName: t.fileName, duration: t.duration, trackNumber: t.number)
                tr.id = t.id; tr.lyricsLRC = t.lrc; tr.mixtape = mx
                c.insert(tr)
            }
        }
        let moods = (try? c.fetch(FetchDescriptor<MoodPlaylist>())) ?? []
        for m in b.moods where !moods.contains(where: { $0.id == m.id }) {
            let p = MoodPlaylist(name: m.name, summary: m.summary, prompt: m.prompt, recipeData: m.recipe, trackIDs: m.tracks)
            p.id = m.id; p.autoRefresh = m.autoRefresh
            c.insert(p)
        }
        for id in b.pinnedPlaylists where Store.shared.pinnedPlaylist(UInt64(bitPattern: id)) == nil {
            c.insert(PinnedPlaylist(playlistID: UInt64(bitPattern: id)))
        }
        if b.albumGroups != nil || b.albumSplits != nil { AlbumGroups.restore(groups: b.albumGroups ?? [], split: b.albumSplits ?? []) }
        if let sides = b.vinylSides { VinylSides.shared.replaceAll(sides) }
        if let shelf = b.roomShelf { RoomShelf.shared.set(shelf) }
        if let posters = b.artistPosters { ArtistPosters.shared.restore(posters) }
        Store.shared.save()
        var summary = "Restored \(b.songs.count) song passports, \(b.albums.count) albums, \(b.editions.count) editions, \(b.mixtapes.count) mixtapes and \(b.moods.count) mood playlists."
        if missingAudio > 0 { summary += " \(missingAudio) mixtape tracks need their audio files imported again." }
        return summary
    }
}
