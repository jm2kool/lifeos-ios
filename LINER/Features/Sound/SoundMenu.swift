import SwiftUI

/// The player's sound items: sleep timer, Automix and the equaliser.
struct PlayerSoundMenu: View {
    let equalizer: () -> Void
    @Environment(PlaybackCoordinator.self) private var player
    @AppStorage("automix.mode") private var automix = Automix.Mode.off.rawValue
    @AppStorage("automix.seconds") private var automixSeconds = 6.0

    var body: some View {
        let timer = SleepTimer.shared
        Menu(timer.isOn ? "Sleep Timer · \(timer.label)" : "Sleep Timer", systemImage: "moon.zzz") {
            if timer.isOn {
                Button("Add 10 Minutes", systemImage: "plus") { timer.extend(minutes: 10, player: player) }
                Button("Turn Off", systemImage: "xmark", role: .destructive) { timer.cancel() }
                Divider()
            }
            ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                Button("\(m) Minutes") { timer.start(.minutes(m), player: player) }
            }
            Button("End of This Song") { timer.start(.endOfSong, player: player) }
            Button("End of the Queue") { timer.start(.endOfQueue, player: player) }
        }
        Menu("Automix", systemImage: "point.3.connected.trianglepath.dotted") {
            Button { automix = Automix.Mode.off.rawValue } label: { check("Off", automix == Automix.Mode.off.rawValue) }
            ForEach([3.0, 6.0, 9.0, 12.0], id: \.self) { s in
                Button {
                    automix = Automix.Mode.crossfade.rawValue
                    automixSeconds = s
                } label: { check("Crossfade · \(Int(s)) s", automix == Automix.Mode.crossfade.rawValue && automixSeconds == s) }
            }
        }
        Button("Equaliser", systemImage: "slider.vertical.3", action: equalizer)
    }

    @ViewBuilder private func check(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

/// A small moon and the time left, on the player while the sleep timer runs. Tap for more time or to stop it.
struct SleepBadge: View {
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        let timer = SleepTimer.shared
        if timer.isOn {
            Menu {
                Button("Add 10 Minutes", systemImage: "plus") { timer.extend(minutes: 10, player: player) }
                Button("Turn Off", systemImage: "xmark", role: .destructive) { timer.cancel() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "moon.fill").font(.system(size: 10, weight: .semibold))
                    Text(timer.label).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 10).frame(height: 24)
                .glassEffect(.regular, in: .capsule)
            }
            .accessibilityLabel("Sleep timer, \(timer.label) left")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Menu("Sound") { PlayerSoundMenu {} }
        SleepBadge()
    }
    .padding().background(.black).environment(PreviewData.player).preferredColorScheme(.dark)
}
