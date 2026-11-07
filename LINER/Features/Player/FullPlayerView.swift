import SwiftUI

/// The full player: the cover always fills the whole screen (never a letterboxed square), with the
/// controls on glass tinted by the artwork. Swipe down to drop back to the mini player.
struct FullPlayerView: View {
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var art = PlayerArtwork()
    @State private var drag: CGFloat = 0
    @State private var sheet: PlayerSheet?

    enum PlayerSheet: String, Identifiable { case queue, lyrics, songPassport; var id: String { rawValue } }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let item = player.current { bottom(item) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .offset(y: max(0, drag))
        .gesture(DragGesture(minimumDistance: 20)
            .onChanged { if $0.translation.height > 0 { drag = $0.translation.height } }
            .onEnded { v in
                if v.translation.height > 140 || v.predictedEndTranslation.height > 400 { dismiss() }
                withAnimation(.liner) { drag = 0 }
            })
        .task(id: player.current?.artworkKey) { await art.load(player.current) }
        .sheet(item: $sheet) { which in
            switch which {
            case .queue: QueueSheet().presentationDetents([.medium, .large])
            case .lyrics: PlayerExtras.lyrics()
            case .songPassport: PlayerExtras.songPassport(for: player.current)
            }
        }
        .statusBarHidden(drag > 0)
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
            PlayerExtras.moreMenu(dismiss: { dismiss() })
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
        .environment(PreviewData.library).environment(PreviewData.player)
        .preferredColorScheme(.dark)
}
