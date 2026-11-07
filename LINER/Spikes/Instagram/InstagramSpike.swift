import SwiftUI
import UIKit

/// Spike E: Matinee only ever sends `backgroundImage` + `stickerImage`. This checks the `backgroundVideo`
/// key LINER needs for animated story cards, using the same Facebook app ID.
@MainActor @Observable
final class InstagramSpike {
    static let shared = InstagramSpike()

    enum Kind: String, CaseIterable {
        case still = "Still background (Matinee's way)"
        case video = "Video background"
        case videoSticker = "Video background + sticker"
    }

    private(set) var story: LoopVideoMaker.Output?
    private(set) var sticker: UIImage?
    private(set) var working = false
    private let report = SpikeReport.shared

    private var url: URL? {
        let id = AppBrand.facebookAppID.isEmpty ? (Bundle.main.bundleIdentifier ?? "") : AppBrand.facebookAppID
        return URL(string: "instagram-stories://share?source_application=\(id)")
    }

    var installed: Bool { url.map { UIApplication.shared.canOpenURL($0) } ?? false }

    /// A 9:16 Living Cover (1080×1920, 8 s) from the test song's artwork, plus a small sticker.
    func prepare() async {
        working = true
        defer { working = false }
        let item = LibrarySpike.shared.selected
        let cover = item?.artwork?.image(at: CGSize(width: 1400, height: 1400)) ?? LoopVideoMaker.placeholderCover(title: "LINER.")
        do {
            story = try await LoopVideoMaker.make(from: cover, width: 1080, height: 1920, name: "story")
            let size = (try? story?.video.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            report.log(.instagram, "Story video ready: 1080×1920, 8 s, H.264, \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
        } catch {
            report.log(.instagram, "Story video FAILED: \(error.localizedDescription)")
        }
        let renderer = ImageRenderer(content: StickerCard(title: item?.title ?? "Test song", artist: item?.artist ?? AppBrand.name))
        renderer.scale = 3
        sticker = renderer.uiImage
    }

    func share(_ kind: Kind) async {
        if story == nil { await prepare() }
        guard let url, let story else { return }
        report.log(.instagram, "Facebook app ID: \(AppBrand.facebookAppID.isEmpty ? "MISSING (using bundle ID)" : AppBrand.facebookAppID) · Instagram installed: \(installed)")
        guard installed else {
            report.set(.instagram, .fails, because: "canOpenURL(instagram-stories://) is false — is Instagram installed?")
            return
        }
        var item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundTopColor": "#1A1A1A",
            "com.instagram.sharedSticker.backgroundBottomColor": "#000000",
        ]
        switch kind {
        case .still:
            item["com.instagram.sharedSticker.backgroundImage"] = story.preview.jpegData(compressionQuality: 0.92)
        case .video, .videoSticker:
            guard let data = try? Data(contentsOf: story.video) else { report.log(.instagram, "Couldn't read the video"); return }
            item["com.instagram.sharedSticker.backgroundVideo"] = data
            if kind == .videoSticker, let png = sticker?.pngData() { item["com.instagram.sharedSticker.stickerImage"] = png }
        }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date.now.addingTimeInterval(5 * 60)])
        let opened = await UIApplication.shared.open(url)
        report.log(.instagram, "\(kind.rawValue): pasteboard set (\(item.keys.count) keys), open() returned \(opened)")
    }
}

/// The movable sticker for the third test.
struct StickerCard: View {
    let title: String
    let artist: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW PLAYING").font(.system(size: 10, weight: .semibold)).tracking(2.5).foregroundStyle(.white.opacity(0.6))
            Text(title).font(.system(size: 26, design: .serif)).lineLimit(2)
            Text(artist.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(.white.opacity(0.7))
            Text(AppBrand.name).font(.system(size: 14, design: .serif)).padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 260, alignment: .leading)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
