import SwiftUI

/// One move in the Listening Room, then `next` once it's done. A timer backs up SwiftUI's own "finished", which
/// never comes when nothing on screen changed (putting a record on) and used to leave the room stuck.
@MainActor
enum RoomStep {
    static func run(_ seconds: Double, _ animation: Animation, _ changes: () -> Void, then next: @escaping () -> Void) {
        let once = Once(next)
        withAnimation(animation, changes) { once.run() }
        Task { try? await Task.sleep(for: .seconds(seconds + 0.1)); once.run() }
    }
}

/// Runs its closure the first time it's asked, and never again.
@MainActor private final class Once {
    private var action: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func run() { let a = action; action = nil; a?() }
}
