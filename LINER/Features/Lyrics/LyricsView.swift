import SwiftUI

/// The three looks for full-screen lyrics.
enum LyricsStyle: String, CaseIterable, Identifiable {
    case singAlong, video, behind
    var id: String { rawValue }
    var label: String {
        switch self { case .singAlong: "Sing-along"; case .video: "Lyric video"; case .behind: "Behind the cover" }
    }
    var symbol: String {
        switch self { case .singAlong: "text.alignleft"; case .video: "play.rectangle"; case .behind: "person.and.background.dotted" }
    }
}

/// Full-screen lyrics (SPEC §6.6): the whole screen becomes the song. Every word fills with light as it's sung,
/// over the cover's colours in motion (Sing-along), or one huge line at a time over the cover (Lyric video), or
/// giant letters behind the person on the cover (Behind the cover). The controls fade away after a few seconds;
/// touch to bring them back. Tap a line to jump there; hold it to save or share it.
struct LyricsView: View {
    @Environment(PlaybackCoordinator.self) var player
    @Environment(\.dismiss) var dismiss
    @AppStorage("lyricsStyle") var styleRaw = LyricsStyle.singAlong.rawValue
    @State var lyrics: Lyrics?
    @State var loading = true
    @State var art = PlayerArtwork()
    @State var colours = AlbumColours.black
    @State var cutout: UIImage?
    @State var saved: String?
    @State var sharing: ShareContent?
    /// Choosing lines to share, and the lines chosen (always one unbroken run).
    @State var selecting = false
    @State var picked: ClosedRange<Int>?
    @State var controls = true
    @State var lastTouch = Date.now
    @State var nudge = 0.0
    @State var listening = false

    /// Story cards hold a few lines, like Apple Music's.
    static let maxLines = 6, maxCharacters = 220

    var style: LyricsStyle {
        let s = LyricsStyle(rawValue: styleRaw) ?? .singAlong
        return s == .behind && cutout == nil && art.image != nil && !loading ? .singAlong : s
    }

    /// Where the song is, for the words: a touch ahead to make up for the screen, plus your nudge.
    func now() -> Double { player.currentTime + 0.1 + nudge }

    var body: some View {
        ZStack {
            backdrop
            content
            chrome.opacity(controls || selecting ? 1 : 0).allowsHitTesting(controls || selecting)
        }
        .contentShape(Rectangle())
        .onTapGesture { touch() }
        .statusBarHidden(!controls)
        .persistentSystemOverlays(controls ? .automatic : .hidden)
        .task(id: player.current?.id) { await load() }
        .task(id: styleRaw) {
            guard styleRaw == LyricsStyle.behind.rawValue, cutout == nil, let img = art.image, let item = player.current else { return }
            cutout = await SubjectMask.cutout(img, key: CoverArt.key(for: item))
            if cutout == nil { flash("This cover has no clear subject, so it stays in Sing-along") }
        }
        .task(id: lastTouch) {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.isPlaying, !selecting, lyrics?.isSynced == true else { return }
            withAnimation(.easeInOut(duration: 0.6)) { controls = false }
        }
        .safeAreaInset(edge: .bottom) { if selecting { shareBar.transition(.move(edge: .bottom).combined(with: .opacity)) } }
        .animation(.liner, value: selecting)
        .animation(.easeInOut(duration: 0.5), value: style)
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing { ShareCardSheet(content: sharing) }
        }
        .overlay(alignment: .bottom) {
            if let saved {
                Text(saved).font(.footnote).padding(12).glassEffect(.regular, in: Capsule()).padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task { try? await Task.sleep(for: .seconds(2.4)); withAnimation { self.saved = nil } }
            }
        }
        .preferredColorScheme(.dark)
    }

    func touch() {
        lastTouch = .now
        if !controls { withAnimation(.easeInOut(duration: 0.3)) { controls = true } }
    }

    private func load() async {
        loading = true
        lyrics = nil
        cutout = nil
        guard let item = player.current else { loading = false; return }
        nudge = LyricsNudge.offset(item.id)
        await art.load(item)
        if let img = art.image {
            let key = CoverArt.key(for: item)
            let found = await AlbumPalette.colours(for: img, key: key)
            withAnimation(.easeInOut(duration: 0.8)) { colours = found }
            if LyricsStyle(rawValue: styleRaw) == .behind { cutout = await SubjectMask.cutout(img, key: key) }
        }
        lyrics = await LyricsStore.lyrics(for: item)
        withAnimation(.liner) { loading = false }
    }

    // MARK: Background

    @ViewBuilder private var backdrop: some View {
        switch style {
        case .singAlong:
            LyricsBackdrop(colours: colours, playing: player.isPlaying)
        case .video:
            ZStack {
                colours.background
                if let img = art.image {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        FocusedFillImage(image: img, focus: art.look.focus).scaleEffect(1.08 + 0.06 * sin(t / 9))
                    }
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .clear, location: 0.3),
                                       .init(color: colours.background.opacity(0.55), location: 0.62), .init(color: .black.opacity(0.88), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        case .behind:
            ZStack {
                colours.background
                if let img = art.image { FocusedFillImage(image: img, focus: art.look.focus) }
                colours.background.opacity(0.25)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Lyrics

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().tint(.white)
        } else if let lyrics, lyrics.isSynced, !selecting {
            switch style {
            case .singAlong: singAlong(lyrics)
            case .video: LyricVideoStage(lyrics: lyrics, colours: colours, clock: now)
            case .behind: BehindCoverStage(lyrics: lyrics, colours: colours, cutout: cutout, focus: art.look.focus, clock: now)
            }
        } else if selecting {
            pickList
        } else if let plain = lyrics?.plain {
            ScrollView {
                Text(plain).font(.system(size: 26, weight: .bold)).lineSpacing(8).padding(24).padding(.top, 90)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        } else {
            EmptyStateView(symbol: "quote.bubble", title: "No lyrics found",
                           message: player.current?.isLibrary == false ? "Add an .lrc file to this mixtape track in its editor." : "LRCLIB doesn't have this song yet.")
        }
    }

    // MARK: Controls

    private var chrome: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            if !selecting {
                VStack(spacing: 14) {
                    Scrubber()
                    TransportControls(tint: colours.accent)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(.horizontal, 12).padding(.bottom, 4)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let item = player.current {
                QueueItemArtwork(item: item, cornerRadius: 8).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        if let lyrics, lyrics.isSynced { badge(lyrics.timing) }
                    }
                }
            }
            Spacer()
            if selecting {
                Button("Cancel") { stopSelecting() }.font(.system(size: 15, weight: .semibold)).buttonStyle(.plain)
            } else {
                LyricsMenu(view: self)
                GlassCircleButton(systemImage: "xmark", label: "Close lyrics", size: 40) { dismiss() }
            }
        }
        .padding(.horizontal, 18).padding(.top, 10)
    }

    private func badge(_ timing: Lyrics.Timing) -> some View {
        Text(timing == .word ? "WORD-TIMED" : "ESTIMATED")
            .font(.system(size: 8.5, weight: .bold)).tracking(1.2)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(.white.opacity(timing == .word ? 0.28 : 0.14), in: Capsule())
            .accessibilityLabel(timing == .word ? "Word-timed lyrics" : "Word timings estimated")
    }

    func flash(_ text: String) { withAnimation { saved = text } }
}

#Preview {
    LyricsView()
        .environment(PreviewData.player).environment(PreviewData.library).modelContainer(Store.shared.container)
}
