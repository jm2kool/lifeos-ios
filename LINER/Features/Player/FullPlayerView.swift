import SwiftUI

/// The full player: the cover always fills the whole screen (never a letterboxed square), with the
/// controls on glass tinted by the artwork. Pull down to shrink back into the mini player: that's the system's
/// own interactive zoom dismissal, so it tracks your finger smoothly.
struct FullPlayerView: View {
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var art = PlayerArtwork()
    @State private var sheet: PlayerSheet?
    @AppStorage("playerVinyl") private var vinyl = false

    enum PlayerSheet: String, Identifiable { case queue, lyrics, songPassport, share; var id: String { rawValue } }

    var body: some View {
        ZStack {
            background
            if vinyl { vinylBackdrop.transition(.opacity) }
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                if vinyl, let item = player.current {
                    PlayerVinyl(item: item)
                        .frame(maxWidth: 440)
                        .frame(maxWidth: .infinity)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    Spacer(minLength: 12)
                }
                if let item = player.current { bottom(item) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .keepsScreenAwake()
        .task(id: player.current.map { CoverArt.key(for: $0) }) { await art.load(player.current) }
        .task { await Demo.playerOpened(open: { sheet = $0 }, record: { withAnimation(.liner) { vinyl = true } }) }
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

    /// Behind the record: the cover blurred right down, so the record stands out on its own.
    private var vinylBackdrop: some View {
        ZStack {
            Color.black
            if let image = art.image { FillImage(image: image).blur(radius: 60).opacity(0.55).scaleEffect(1.3) }
            LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// The album's name above the player, left out for a song on its own.
    private var albumLine: String {
        guard let item = player.current else { return "" }
        if let song = item.song { return library.snapshot.albumOf(song)?.title ?? "" }
        return item.albumTitle
    }

    private var topBar: some View {
        HStack {
            GlassCircleButton(systemImage: "chevron.down", label: "Close player", size: 42) { dismiss() }
            Spacer()
            Text(albumLine).linerLabel(size: 10).lineLimit(1).padding(.horizontal, 8)
            Spacer()
            // Always in reach: flips between the full cover and the spinning record.
            GlassCircleButton(systemImage: vinyl ? "photo" : "record.circle", label: vinyl ? "Show the cover" : "Show as a record", size: 42) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { vinyl.toggle() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .padding(.trailing, 6)
            PlayerExtras.moreMenu(item: player.current, dismiss: { dismiss() }, share: { sheet = .share }, lyrics: { sheet = .lyrics })
        }
        .padding(.top, 8)
    }

    private func bottom(_ item: QueueItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            NowPlayingLyrics(item: item) { sheet = .lyrics }
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
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container)
        .preferredColorScheme(.dark)
}
