@preconcurrency import MediaPlayer
import SwiftData
import UIKit

/// Builds the lock screen's animated artwork (SPEC §5): the user's motion cover if there is one, otherwise a
/// Living Cover, in 3:4 (full-screen layout) and 1:1. One `artworkID` per album, so songs share it.
@MainActor
final class AnimatedArtwork {
    private var prepared: [String: [String: Any]] = [:]
    private var preparing: Set<String> = []
    weak var nowPlaying: NowPlayingManager?

    /// Setting: also try the animated lock screen for Apple Music songs (the queue player owns Now Playing there).
    static var forLibrarySongs: Bool { UserDefaults.standard.object(forKey: "animatedLockForLibrary") as? Bool ?? true }

    /// Keys for Now Playing, if ready. Starts preparing them otherwise (and refreshes Now Playing when done).
    func keys(for item: QueueItem) -> [String: Any] {
        guard MotionSettings.livingCoversOn || MotionLookup.file(for: item) != nil else { return [:] }
        if item.isLibrary && !Self.forLibrarySongs { return [:] }
        let supported = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        guard supported.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork) || supported.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork) else { return [:] }
        if let ready = prepared[CoverArt.key(for: item)] { return ready }
        prepare(item)
        return [:]
    }

    private func prepare(_ item: QueueItem) {
        let key = CoverArt.key(for: item)
        guard !preparing.contains(key) else { return }
        preparing.insert(key)
        let motion = MotionLookup.file(for: item)
        Task {
            defer { preparing.remove(key) }
            var keys: [String: Any] = [:]
            if let motion {
                let source = MotionCoverFiles.url(motion)
                for (aspect, infoKey) in [(LivingCoverRenderer.Aspect.tall, MPNowPlayingInfoProperty3x4AnimatedArtwork),
                                          (.square, MPNowPlayingInfoProperty1x1AnimatedArtwork)] {
                    guard let url = await MotionCrop.crop(source, to: aspect), let preview = await MotionCrop.preview(url) else { continue }
                    keys[infoKey] = Self.artwork(id: "motion-\(aspect.rawValue)-\(motion)", preview: preview, video: { url })
                }
            } else if let image = await CoverArt.image(for: item, pixels: 1400) {
                let style = LivingCoverRenderer.Style.current
                for (aspect, infoKey) in [(LivingCoverRenderer.Aspect.tall, MPNowPlayingInfoProperty3x4AnimatedArtwork),
                                          (.square, MPNowPlayingInfoProperty1x1AnimatedArtwork)] {
                    guard let preview = LivingCoverRenderer.preview(for: image, aspect: aspect) else { continue }
                    // The preview is ready now; the video is rendered when the system first asks (it waits up to ~30 s).
                    keys[infoKey] = Self.artwork(id: "living-\(style.rawValue)-\(aspect.rawValue)-\(key)", preview: preview) {
                        await LivingCoverRenderer.video(for: image, key: key, aspect: aspect, style: style)
                    }
                }
            }
            guard !keys.isEmpty else { return }
            prepared[key] = keys
            if prepared.count > 20 { prepared.removeValue(forKey: prepared.keys.first { $0 != key } ?? key) }
            nowPlaying?.update()
        }
    }

    /// Built outside the main actor: the system calls these handlers on its own queue.
    nonisolated private static func artwork(id: String, preview: UIImage, video: @escaping @Sendable () async -> URL?) -> MPMediaItemAnimatedArtwork {
        MPMediaItemAnimatedArtwork(artworkID: id,
                                   previewImageRequestHandler: { @Sendable _ in preview },
                                   videoAssetFileURLRequestHandler: { @Sendable _ in await video() })
    }

    func reset() { prepared.removeAll() }
}

/// Finds the user's motion cover for whatever is playing.
@MainActor
enum MotionLookup {
    /// The user's motion cover for the item's album, edition or mixtape.
    static func file(for item: QueueItem) -> String? {
        if let f = CoverArt.edition(for: item)?.motionCoverFile { return f }
        switch item {
        case .library(let s):
            let id = "album-\(s.albumID)"
            guard let note = Store.shared.albumNote(id) else { return nil }
            if let ed = note.activeEditionID, let e = edition(ed), let f = e.motionCoverFile { return f }
            return note.motionCoverFile
        case .local(let t):
            guard let mid = t.mixtapeID else { return nil }
            var d = FetchDescriptor<Mixtape>(predicate: #Predicate { $0.id == mid })
            d.fetchLimit = 1
            return (try? Store.shared.context.fetch(d).first)?.motionCoverFile
        }
    }

    private static func edition(_ id: UUID) -> Edition? {
        var d = FetchDescriptor<Edition>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? Store.shared.context.fetch(d).first
    }

}
