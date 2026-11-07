import SwiftUI

/// The full player: the cover always fills the whole screen (never a letterboxed square), with the
/// controls on glass tinted by the artwork. Pull down to shrink back into the mini player: that's the system's
/// own interactive zoom dismissal, so it tracks your finger smoothly.
struct FullPlayerView: View {
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var art = PlayerArtwork()
    @State private var sheet: PlayerSheet?
    @AppStorage("playerVinyl") private var vinyl = false

    enum PlayerSheet: String, Identifiable { case queue, lyrics, songPassport, share; var id: String { rawValue } }

    var body: some View {
        ZStack {
            background
            if vinyl { Color.black.opacity(0.55).ignoresSafeArea().transition(.opacity) }
            VStack(spacing: 0) {
                topBar
                if vinyl, let item = player.current {
                    PlayerVinyl(item: item).padding(.horizontal, 12).padding(.vertical, 18)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Spacer()
                }
                if let item = player.current { bottom(item) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .task(id: player.current?.coverKey) { await art.load(player.current) }
        .sheet(item: $sheet) { which in
            switch which {
            case .queue: QueueSheet().presentationDetents([.medium, .large])
            case .lyrics: PlayerExtras.lyrics()
            case .songPassport: PlayerExtras.songPassport(for: player.current)
            case .share: if let item = player.current { ShareCardSheet(content: .nowPlaying(item)) }
            }
        }
    }

    private var background: some View {
        ZStack {
            art.look.dominant.opacity(0.6)
            PlayerExtras.background(item: player.current, image: art.image, look: art.look)
                .id(art.key)
                .transition(.opacity)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.42),
                .init(color: art.look.secondary.mix(with: .black, by: 0.55).opacity(0.85), location: 0.66),
                .init(color: .black.opacity(0.96), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: art.key)
    }

    private var topBar: some View {
        HStack {
            GlassCircleButton(systemImage: "chevron.down", label: "Close player", size: 42) { dismiss() }
            Spacer()
            Text(player.current?.albumTitle ?? "").linerLabel(size: 10).lineLimit(1).padding(.horizontal, 8)
            Spacer()
            PlayerExtras.moreMenu(item: player.current, dismiss: { dismiss() }, share: { sheet = .share }, lyrics: { sheet = .lyrics })
        }
        .padding(.top, 8)
    }

    private func bottom(_ item: QueueItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.serif(32)).lineLimit(2).minimumScaleFactor(0.7)
                    Text(item.artist).linerLabel(size: 12).foregroundStyle(.white.opacity(0.75))
                }
                .id(item.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                Spacer()
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        GlassCircleButton(systemImage: "text.book.closed", label: "Song Passport", size: 44) { sheet = .songPassport }
                        PlayerExtras.heartButton(for: item)
                    }
                }
            }
            .animation(.liner, value: item.id)
            Scrubber()
            TransportControls(tint: art.look.dominant).frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(Palette.secondary)
                VolumeSlider().frame(height: 34)
                RoutePicker().frame(width: 30, height: 30)
                Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { vinyl.toggle() } } label: {
                    Image(systemName: vinyl ? "record.circle.fill" : "record.circle")
                }
                .accessibilityLabel(vinyl ? "Show the cover" : "Show as a record")
                Button { sheet = .lyrics } label: { Image(systemName: "quote.bubble") }.accessibilityLabel("Lyrics")
                Button { sheet = .queue } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Queue")
            }
            .font(.system(size: 18))
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    FullPlayerView()
        .environment(PlaybackCoordinator(library: PreviewData.library))
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container)
        .preferredColorScheme(.dark)
}
