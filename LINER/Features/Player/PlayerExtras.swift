import SwiftUI

/// Pieces of the full player that later phases fill in (motion backgrounds, lyrics, passports, hearts).
@MainActor
enum PlayerExtras {
    /// Full-screen background: your motion cover, else a Living Cover, else the still (always filling the screen).
    @ViewBuilder static func background(item: QueueItem?, image: UIImage?, look: ArtworkLook) -> some View {
        if let item, let motion = MotionLookup.file(for: item) {
            LoopingVideo(url: MotionCoverFiles.url(motion))
        } else if let image, let item, MotionSettings.livingCoversOn {
            LivingCoverView(image: image, look: look, key: item.coverKey)
        } else if let image {
            FocusedFillImage(image: image, focus: look.focus)
        } else {
            Color.clear
        }
    }

    @ViewBuilder static func lyrics() -> some View {
        LyricsView().presentationDetents([.large]).presentationBackground(.black)
    }

    @ViewBuilder static func songPassport(for item: QueueItem?) -> some View {
        if let item { SongPassportSheet(item: item) }
    }

    @ViewBuilder static func heartButton(for item: QueueItem) -> some View {
        HeartButton(item: item)
    }

    @ViewBuilder static func moreMenu(item: QueueItem?, dismiss: @escaping () -> Void, share: @escaping () -> Void,
                                      lyrics: @escaping () -> Void) -> some View {
        Menu {
            Button("Share Now Playing", systemImage: "square.and.arrow.up", action: share)
            Button("Lyrics", systemImage: "quote.bubble", action: lyrics)
            PlayerMenuExtras(item: item)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 42, height: 42)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("More")
    }
}
