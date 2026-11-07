import SwiftUI

/// Share entry point for recap story cards.
@MainActor
enum ShareCardLauncher {
    @ViewBuilder static func recap(card: RecapStoryView.Card, recap: Recap, cover: UIImage?) -> some View {
        ShareCardButton(make: { .recap(recap, card: card) }, label: "Share this card")
            .buttonStyle(.linerGlass).controlSize(.large)
    }
}
