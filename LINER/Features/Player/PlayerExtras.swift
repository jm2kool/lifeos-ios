import SwiftUI

/// Pieces of the full player that later phases fill in (motion backgrounds, lyrics, passports, hearts).
@MainActor
enum PlayerExtras {
    @ViewBuilder static func background(item: QueueItem?, image: UIImage?, look: ArtworkLook) -> some View {
        if let image { FocusedFillImage(image: image, focus: look.focus) } else { Color.clear }
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

    @ViewBuilder static func moreMenu(dismiss: @escaping () -> Void) -> some View {
        Menu {
            Text("More options are coming")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 42, height: 42)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("More")
    }
}
