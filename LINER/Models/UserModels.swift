import Foundation
import SwiftData

/// A favourite moment in a song: a timestamp and an optional name.
struct Moment: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var seconds: Double
    var name: String
}

/// How a pinned album or playlist shows on Home.
enum PinAppearance: String, Codable, CaseIterable, Sendable {
    case artistPortrait, albumArtwork
    var label: String { self == .artistPortrait ? "Artist Portrait" : "Album Artwork" }
}

/// One track of a Personal Edition: a library song or a mixtape track.
enum EditionTrack: Codable, Hashable, Sendable {
    case library(MediaKey)
    case mixtape(UUID)
}

/// JSON helpers for the few structured fields stored as Data.
enum Coding {
    static func encode<T: Encodable>(_ value: T) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? { try? JSONDecoder().decode(type, from: data) }
}

/// Song Passport (SPEC §6.8). `itemID` is "lib-<persistentID>" or "loc-<uuid>" (QueueItem.id).
@Model final class SongNote {
    @Attribute(.unique) var itemID: String
    var keyData: Data
    var rating: Int?
    var moods: [String]
    var notes: String
    var connection: String
    var momentsData: Data
    var lyricLines: [String]
    var updatedAt: Date

    init(itemID: String, key: MediaKey?) {
        self.itemID = itemID
        keyData = key.map(Coding.encode) ?? Data()
        moods = []
        notes = ""
        connection = ""
        momentsData = Coding.encode([Moment]())
        lyricLines = []
        updatedAt = .now
    }

    var key: MediaKey? { Coding.decode(MediaKey.self, keyData) }
    var moments: [Moment] {
        get { Coding.decode([Moment].self, momentsData) ?? [] }
        set { momentsData = Coding.encode(newValue.sorted { $0.seconds < $1.seconds }); updatedAt = .now }
    }
    var isEmpty: Bool {
        rating == nil && moods.isEmpty && notes.isEmpty && connection.isEmpty && moments.isEmpty && lyricLines.isEmpty
    }
}

/// Album Passport plus pins and covers. `albumID` is "album-<persistentID>" or "mixtape-<uuid>" (QueueItem.artworkKey).
@Model final class AlbumNote {
    @Attribute(.unique) var albumID: String
    var keyData: Data
    var rating: Int?
    /// Your own order, as item IDs.
    var personalRanking: [String]
    var pinned: Bool
    var pinnedAt: Date?
    var pinnedAppearanceRaw: String
    /// File name of a user motion cover in Application Support/LINER/MotionCovers.
    var motionCoverFile: String?
    @Attribute(.externalStorage) var coverOverride: Data?
    var activeEditionID: UUID?

    init(albumID: String, key: AlbumKey?) {
        self.albumID = albumID
        keyData = key.map(Coding.encode) ?? Data()
        personalRanking = []
        pinned = false
        pinnedAppearanceRaw = PinAppearance.artistPortrait.rawValue
    }

    var key: AlbumKey? { Coding.decode(AlbumKey.self, keyData) }
    var pinnedAppearance: PinAppearance {
        get { PinAppearance(rawValue: pinnedAppearanceRaw) ?? .artistPortrait }
        set { pinnedAppearanceRaw = newValue.rawValue }
    }
}

/// A Personal Edition: your own version of an album (or a mix of library and mixtape tracks).
@Model final class Edition {
    @Attribute(.unique) var id: UUID
    var baseAlbumID: String?
    var title: String
    var tracksData: Data
    @Attribute(.externalStorage) var coverImage: Data?
    var motionCoverFile: String?
    var isActive: Bool
    var createdAt: Date

    init(title: String, baseAlbumID: String?, tracks: [EditionTrack]) {
        id = UUID()
        self.title = title
        self.baseAlbumID = baseAlbumID
        tracksData = Coding.encode(tracks)
        isActive = false
        createdAt = .now
    }

    var tracks: [EditionTrack] {
        get { Coding.decode([EditionTrack].self, tracksData) ?? [] }
        set { tracksData = Coding.encode(newValue) }
    }
}

/// An imported "album" of your own audio files.
@Model final class Mixtape {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var label: String?
    var year: Int?
    @Attribute(.externalStorage) var coverImage: Data?
    var motionCoverFile: String?
    var showInHome: Bool
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MixtapeTrack.mixtape) var tracks: [MixtapeTrack] = []

    init(title: String, artist: String) {
        id = UUID()
        self.title = title
        self.artist = artist
        showInHome = true
        createdAt = .now
    }

    var orderedTracks: [MixtapeTrack] { tracks.sorted { $0.trackNumber < $1.trackNumber } }
}

@Model final class MixtapeTrack {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    /// File name inside Application Support/LINER/Mixtapes.
    var fileName: String
    var duration: Double
    var trackNumber: Int
    var lyricsLRC: String?
    var mixtape: Mixtape?

    init(title: String, artist: String, fileName: String, duration: Double, trackNumber: Int) {
        id = UUID()
        self.title = title
        self.artist = artist
        self.fileName = fileName
        self.duration = duration
        self.trackNumber = trackNumber
    }
}

/// A song's play count on a day, written only when it changed (recaps).
@Model final class PlaySnapshot {
    var date: Date
    var persistentID: Int64
    var playCount: Int

    init(date: Date, persistentID: UInt64, playCount: Int) {
        self.date = date
        self.persistentID = Int64(bitPattern: persistentID)
        self.playCount = playCount
    }
}

/// A play inside LINER., timed precisely (recaps, mixtape stats).
@Model final class PlayEvent {
    var itemID: String
    var persistentID: Int64?
    var mixtapeTrackID: UUID?
    var startedAt: Date
    var listenedSeconds: Double
    var completed: Bool
    var title: String
    var artist: String
    var album: String
    var albumKey: String
    var genre: String
    var duration: Double

    init(record: PlayRecord) {
        let item = record.item
        itemID = item.id
        persistentID = item.libraryID.map { Int64(bitPattern: $0) }
        mixtapeTrackID = item.local?.id
        startedAt = record.startedAt
        listenedSeconds = record.listened
        completed = record.completed
        title = item.title
        artist = item.artist
        album = item.albumTitle
        albumKey = item.artworkKey
        genre = item.song?.genre ?? "Mixtape"
        duration = item.duration
    }
}

@Model final class PinnedPlaylist {
    @Attribute(.unique) var playlistID: Int64
    var appearanceRaw: String
    var pinnedAt: Date

    init(playlistID: UInt64) {
        self.playlistID = Int64(bitPattern: playlistID)
        appearanceRaw = PinAppearance.albumArtwork.rawValue
        pinnedAt = .now
    }
}

@Model final class MoodPlaylist {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var prompt: String
    var recipeData: Data
    var trackIDs: [String]
    var createdAt: Date
    var refreshedAt: Date
    var autoRefresh: Bool

    init(name: String, summary: String, prompt: String, recipeData: Data, trackIDs: [String]) {
        id = UUID()
        self.name = name
        self.summary = summary
        self.prompt = prompt
        self.recipeData = recipeData
        self.trackIDs = trackIDs
        createdAt = .now
        refreshedAt = .now
        autoRefresh = false
    }
}

@Model final class LyricsCache {
    @Attribute(.unique) var itemID: String
    var lrc: String?
    var plain: String?
    var fetchedAt: Date

    init(itemID: String, lrc: String?, plain: String?) {
        self.itemID = itemID
        self.lrc = lrc
        self.plain = plain
        fetchedAt = .now
    }
}

enum UserModels {
    static let all: [any PersistentModel.Type] = [SongNote.self, AlbumNote.self, Edition.self, Mixtape.self, MixtapeTrack.self,
                                                  PlaySnapshot.self, PlayEvent.self, PinnedPlaylist.self, MoodPlaylist.self, LyricsCache.self]
}
