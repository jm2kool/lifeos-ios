@preconcurrency import AVFoundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Brings audio files into LINER. (SPEC §6.15): copies them into App Support/Mixtapes, pulls the audio out of
/// video containers, and reads embedded title, artist, album and artwork to pre-fill the mixtape.
enum MixtapeImporter {
    static let allowedTypes: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .mpeg4Movie, .quickTimeMovie, .movie]

    struct Imported: Sendable {
        let fileName: String
        let title: String
        let artist: String?
        let album: String?
        let artwork: Data?
        let duration: Double
    }

    /// Imports files (security-scoped URLs from the file picker or "Open in LINER.").
    static func importFiles(_ urls: [URL]) async -> [Imported] {
        var out: [Imported] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let item = await importOne(url) { out.append(item) }
        }
        return out
    }

    @concurrent
    static func importOne(_ source: URL) async -> Imported? {
        let type = UTType(filenameExtension: source.pathExtension)
        let isVideo = type?.conforms(to: .movie) == true || type?.conforms(to: .mpeg4Movie) == true
        let id = UUID().uuidString
        let fileName: String
        if isVideo {
            fileName = "\(id).m4a"
            guard await extractAudio(source, to: MixtapeFiles.url(fileName)) else { return nil }
        } else {
            fileName = "\(id).\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased())"
            do { try FileManager.default.copyItem(at: source, to: MixtapeFiles.url(fileName)) } catch { return nil }
        }
        let asset = AVURLAsset(url: MixtapeFiles.url(fileName))
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let meta = (try? await AVURLAsset(url: source).load(.commonMetadata)) ?? []
        func string(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: id).first else { return nil }
            let s = try? await item.load(.stringValue)
            return s?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        var artwork: Data?
        if let artItem = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierArtwork).first {
            artwork = try? await artItem.load(.dataValue)
        }
        let fallbackTitle = source.deletingPathExtension().lastPathComponent
        return Imported(fileName: fileName, title: await string(.commonIdentifierTitle) ?? fallbackTitle,
                        artist: await string(.commonIdentifierArtist), album: await string(.commonIdentifierAlbumName),
                        artwork: artwork, duration: duration.isFinite ? duration : 0)
    }

    /// AVAssetExportSession with the Apple M4A preset keeps just the audio.
    @concurrent
    static func extractAudio(_ source: URL, to dest: URL) async -> Bool {
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else { return false }
        try? FileManager.default.removeItem(at: dest)
        do { try await export.export(to: dest, as: .m4a); return true } catch { return false }
    }

    /// Makes a new mixtape from imported files, pre-filled from their metadata. Returns it.
    @MainActor @discardableResult
    static func makeMixtape(from files: [Imported], into existing: Mixtape? = nil) -> Mixtape? {
        guard !files.isEmpty else { return existing }
        let context = Store.shared.context
        let mixtape: Mixtape
        if let existing {
            mixtape = existing
        } else {
            let album = mostCommon(files.compactMap(\.album)) ?? (files.count == 1 ? files[0].title : "New Mixtape")
            mixtape = Mixtape(title: album, artist: mostCommon(files.compactMap(\.artist)) ?? "Unknown Artist")
            if let art = files.compactMap(\.artwork).first, let img = UIImage(data: art) {
                mixtape.coverImage = img.preparingThumbnail(of: CGSize(width: 1400, height: 1400))?.jpegData(compressionQuality: 0.88) ?? art
            }
            context.insert(mixtape)
        }
        var number = (mixtape.tracks.map(\.trackNumber).max() ?? 0) + 1
        for f in files {
            let t = MixtapeTrack(title: f.title, artist: f.artist ?? mixtape.artist, fileName: f.fileName, duration: f.duration, trackNumber: number)
            t.mixtape = mixtape
            context.insert(t)
            number += 1
        }
        Store.shared.save()
        return mixtape
    }

    private static func mostCommon(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// Deletes a mixtape's files with it.
    @MainActor static func delete(_ mixtape: Mixtape) {
        for t in mixtape.tracks { try? FileManager.default.removeItem(at: MixtapeFiles.url(t.fileName)) }
        if let cover = MixtapeFiles.coverURL(for: mixtape) { try? FileManager.default.removeItem(at: cover) }
        Store.shared.context.delete(mixtape)
        Store.shared.save()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension AlbumSubject {
    @MainActor static func mixtape(_ m: Mixtape) -> AlbumSubject {
        AlbumSubject(id: "mixtape-\(m.id.uuidString)", title: m.title, artist: m.artist,
                     tracks: m.orderedTracks.map { .local(TrackResolver.local($0)) }, album: nil)
    }
}
