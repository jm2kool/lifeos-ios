import SwiftUI
import UIKit

extension View {
    /// Stops the screen dimming and locking while this view is on screen (the Now Playing screen, the
    /// turntable, the Listening Room). Counted, so overlapping screens don't switch it back on early.
    func keepsScreenAwake() -> some View { modifier(KeepAwake()) }
}

private struct KeepAwake: ViewModifier {
    @MainActor private static var holders = 0

    func body(content: Content) -> some View {
        content
            .onAppear { Self.change(+1) }
            .onDisappear { Self.change(-1) }
    }

    @MainActor private static func change(_ delta: Int) {
        holders = max(0, holders + delta)
        UIApplication.shared.isIdleTimerDisabled = holders > 0
    }
}
