import SwiftUI

/// Sing-along lyrics (SPEC §6.6): big serif lines over the blurred cover. The active line is bright, past lines
/// fade, future lines are dim; it opens on the line being sung and scrolls to keep it about a third of the way down. Tap a line to
/// jump there; hold it to save the line or make it a favourite moment.
struct LyricsView: View {
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var lyrics: Lyrics?
    @State private var loading = true
    @State private var art = PlayerArtwork()
    @State private var saved: String?
    @State private var sharing: ShareContent?

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                content
            }
        }
        .task(id: player.current?.id) {
            loading = true
            lyrics = nil
            await art.load(player.current)
            if let item = player.current { lyrics = await LyricsStore.lyrics(for: item) }
            loading = false
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing { ShareCardSheet(content: sharing) }
        }
        .overlay(alignment: .bottom) {
            if let saved {
                Text(saved).font(.footnote).padding(12).glassEffect(.regular, in: Capsule()).padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task { try? await Task.sleep(for: .seconds(2)); withAnimation { self.saved = nil } }
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let img = art.image {
                FillImage(image: img).blur(radius: 60).opacity(0.55).scaleEffect(1.3)
            }
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "").font(.serif(20)).lineLimit(1)
                Text(player.current?.artist ?? "").linerLabel(size: 10)
            }
            Spacer()
            GlassCircleButton(systemImage: "xmark", label: "Close lyrics", size: 40) { dismiss() }
        }
        .padding(20)
    }

    @ViewBuilder private var content: some View {
        if loading {
            Spacer(); ProgressView(); Spacer()
        } else if let lyrics, lyrics.isSynced {
            synced(lyrics)
        } else if let plain = lyrics?.plain {
            ScrollView {
                Text(plain).font(.serif(24)).lineSpacing(8).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        } else {
            Spacer()
            EmptyStateView(symbol: "quote.bubble", title: "No lyrics found",
                           message: player.current?.isLibrary == false ? "Add an .lrc file to this mixtape track in its editor." : "LRCLIB doesn't have this song yet.")
            Spacer()
        }
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let active = lyrics.activeIndex(at: player.currentTime + 0.25)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: 200)
                        ForEach(lyrics.lines) { line in
                            lineView(line, state: active.map { line.id < $0 ? -1 : (line.id == $0 ? 0 : 1) } ?? 1)
                                .id(line.id)
                        }
                        Color.clear.frame(height: 420)
                    }
                    .padding(.horizontal, 24)
                }
                .onChange(of: active) { _, now in
                    guard let now else { return }
                    withAnimation(.liner) { proxy.scrollTo(now, anchor: UnitPoint(x: 0.5, y: 0.35)) }
                }
                // Opening the lyrics lands straight on the line being sung, not the top of the song.
                .task(id: lyrics) {
                    let now = lyrics.activeIndex(at: player.currentTime + 0.25) ?? 0
                    proxy.scrollTo(now, anchor: UnitPoint(x: 0.5, y: 0.35))
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(now, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
        }
    }

    /// state: -1 past, 0 active, 1 future.
    private func lineView(_ line: Lyrics.Line, state: Int) -> some View {
        Text(line.text.isEmpty ? "♪" : line.text)
            .font(.serif(state == 0 ? 34 : 30, weight: state == 0 ? .semibold : .regular))
            .foregroundStyle(.white.opacity(state == 0 ? 1 : (state < 0 ? 0.28 : 0.45)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.25), value: state)
            .onTapGesture { player.seek(to: line.time) }
            .contextMenu {
                Button("Save line", systemImage: "bookmark") { save(line: line) }
                Button("Save as favourite moment", systemImage: "star") { saveMoment(line) }
                if let item = player.current, !line.text.isEmpty {
                    Button("Share line", systemImage: "square.and.arrow.up") { sharing = .lyric(item, line: line.text) }
                }
            }
            .accessibilityAddTraits(state == 0 ? .isSelected : [])
            .accessibilityHint("Double-tap to jump here")
    }

    private func save(line: Lyrics.Line) {
        guard let item = player.current, !line.text.isEmpty else { return }
        let note = Store.shared.songNoteOrNew(for: item)
        if !note.lyricLines.contains(line.text) { note.lyricLines.append(line.text) }
        note.updatedAt = .now
        Store.shared.save()
        withAnimation { saved = "Saved to Song Passport" }
    }

    private func saveMoment(_ line: Lyrics.Line) {
        guard let item = player.current else { return }
        let note = Store.shared.songNoteOrNew(for: item)
        note.moments.append(Moment(seconds: line.time, name: line.text))
        Store.shared.save()
        withAnimation { saved = "Saved as a favourite moment" }
    }
}
