@preconcurrency import MediaPlayer
import SwiftUI

/// Spike D screen: grant access, see the library numbers, play a song.
struct LibrarySpikeView: View {
    private let lib = LibrarySpike.shared

    var body: some View {
        SpikePage(spike: .libraryPlayback,
                  intro: "Checks that a free-signed app can read your library and play it with applicationQueuePlayer (no MusicKit). Pick a song here — the lock screen test uses the same one.") {
            if lib.status != .authorized {
                Button("Allow Apple Music access") { Task { await lib.requestAccess() } }
                    .buttonStyle(.glassProminent).controlSize(.large)
                if lib.status == .denied {
                    Text("Access was denied. Turn it on in Settings → Apps → LINER. → Media & Apple Music.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } else {
                transport
                Card {
                    SectionLabel("Your most-played songs")
                    Text("Tap one to play it. Compare a couple of play counts with the Music app.").font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(lib.topSongs, id: \.persistentID) { song in
                        Button { lib.play(song) } label: { row(song) }.buttonStyle(.plain)
                    }
                }
                Button("Rescan library") { lib.scan() }.buttonStyle(.glass)
            }
        }
        .task { if lib.status == .authorized && lib.topSongs.isEmpty { lib.scan() } }
    }

    private var transport: some View {
        Card {
            SectionLabel("Player")
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let t = lib.player.currentPlaybackTime
                Text("\(lib.nowPlayingTitle ?? lib.selected?.title ?? "Nothing") · \(lib.stateText) · \(t.isFinite ? Int(t) : 0)s")
                    .font(.system(.footnote, design: .monospaced))
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Play", systemImage: "play.fill") { if let s = lib.selected { lib.play(s) } }
                    Button("Pause", systemImage: "playpause.fill") { lib.togglePause() }
                    Button("+15s", systemImage: "goforward.15") { lib.skipForward() }
                    Button("Stop", systemImage: "stop.fill") { lib.stop() }
                }
                .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
            }
        }
    }

    private func row(_ song: MPMediaItem) -> some View {
        HStack(spacing: 12) {
            if let img = song.artwork?.image(at: CGSize(width: 88, height: 88)) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? "Untitled").font(.subheadline).lineLimit(1)
                Text(song.artist ?? "").font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            Text("\(song.playCount)").font(.system(size: 18, design: .serif)).monospacedDigit()
            if song.persistentID == lib.selected?.persistentID {
                Image(systemName: "checkmark").foregroundStyle(.green)
            }
        }
    }
}

#Preview { NavigationStack { LibrarySpikeView() }.preferredColorScheme(.dark) }
