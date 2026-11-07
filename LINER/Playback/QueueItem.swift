import Foundation

/// An imported audio file (a mixtape track), played by our own AVPlayer.
struct LocalTrack: Hashable, Sendable, Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var fileURL: URL
    var mixtapeID: UUID?
    var coverURL: URL?
    var lyricsLRC: String?
}

/// One entry in the play queue: a library song or a local file.
enum QueueItem: Hashable, Sendable, Identifiable {
    case library(Song)
    case local(LocalTrack)

    var id: String {
        switch self {
        case .library(let s): "lib-\(s.id)"
        case .local(let t): "loc-\(t.id.uuidString)"
        }
    }
    var title: String { switch self { case .library(let s): s.title; case .local(let t): t.title } }
    var artist: String { switch self { case .library(let s): s.artist; case .local(let t): t.artist } }
    var albumTitle: String { switch self { case .library(let s): s.albumTitle; case .local(let t): t.album } }
    var duration: Double { switch self { case .library(let s): s.duration; case .local(let t): t.duration } }
    var isLibrary: Bool { if case .library = self { true } else { false } }
    var song: Song? { if case .library(let s) = self { s } else { nil } }
    var local: LocalTrack? { if case .local(let t) = self { t } else { nil } }
    var libraryID: UInt64? { song?.id }

    /// Identifies the cover for caching and lock screen `artworkID`s: one per album or mixtape.
    var artworkKey: String {
        switch self {
        case .library(let s): "album-\(s.albumID)"
        case .local(let t): "mixtape-\(t.mixtapeID?.uuidString ?? t.id.uuidString)"
        }
    }
}

enum RepeatMode: String, CaseIterable, Sendable {
    case off, all, one
    var next: RepeatMode { switch self { case .off: .all; case .all: .one; case .one: .off } }
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

/// A finished (or skipped) play, handed to the play log.
struct PlayRecord: Sendable {
    let item: QueueItem
    let startedAt: Date
    let listened: Double
    /// ≥ 50 % or ≥ 4 minutes (SPEC §5).
    var completed: Bool { listened >= 240 || (item.duration > 0 && listened >= item.duration * 0.5) }
}
