import SwiftUI

/// Sing-along lyrics (SPEC §6.6): big serif lines over the blurred cover. The active line is bright, past lines
/// fade, future lines are dim; it opens on the line being sung and scrolls to keep it about a third of the way down. Tap a line to
/// jump there; hold it to save the line or make it a favourite moment. Share picks a run of lines (like Apple Music)
/// and puts them on a story card.
struct LyricsView: View {
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var lyrics: Lyrics?
    @State private var loading = true
    @State private var art = PlayerArtwork()
    @State private var saved: String?
    @State private var sharing: ShareContent?
    /// Choosing lines to share, and the lines chosen (always one unbroken run).
    @State private var selecting = false
    @State private var picked: ClosedRange<Int>?

    /// Story cards hold a few lines, like Apple Music's.
    private static let maxLines = 6, maxCharacters = 220

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
        .safeAreaInset(edge: .bottom) { if selecting { shareBar.transition(.move(edge: .bottom).combined(with: .opacity)) } }
        .animation(.liner, value: selecting)
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
            if selecting {
                Button("Cancel") { stopSelecting() }.font(.system(size: 15, weight: .semibold)).buttonStyle(.plain)
            } else {
                if !allLines.isEmpty {
                    GlassCircleButton(systemImage: "square.and.arrow.up", label: "Share lyrics", size: 40) { startSelecting(at: nil) }
                }
                GlassCircleButton(systemImage: "xmark", label: "Close lyrics", size: 40) { dismiss() }
            }
        }
        .padding(20)
    }

    // MARK: Sharing lines

    /// Every line's text, synced or plain, in order.
    private var allLines: [String] {
        guard let lyrics else { return [] }
        if lyrics.isSynced { return lyrics.lines.map(\.text) }
        return (lyrics.plain ?? "").components(separatedBy: .newlines)
    }

    private var pickedText: [String] {
        guard let picked else { return [] }
        let lines = allLines
        return picked.compactMap { lines.indices.contains($0) ? lines[$0].trimmingCharacters(in: .whitespaces) : nil }.filter { !$0.isEmpty }
    }

    private var shareBar: some View {
        let count = pickedText.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "Choose lines to share" : "\(count) line\(count == 1 ? "" : "s")").font(.system(size: 15, weight: .semibold))
                Text("Up to \(Self.maxLines) lines in a row").font(.caption).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button("Share", systemImage: "square.and.arrow.up") {
                guard let item = player.current, !pickedText.isEmpty else { return }
                sharing = .lyric(item, lines: pickedText)
                stopSelecting()
            }
            .buttonStyle(.linerPrimary).buttonBorderShape(.capsule).disabled(count == 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func startSelecting(at line: Int?) {
        picked = line.map { $0...$0 }
        selecting = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func stopSelecting() { selecting = false; picked = nil }

    /// Tapping grows or shrinks the run from its ends; a line too far away starts a new run there.
    private func pick(_ i: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        guard let r = picked else { picked = i...i; return }
        if r.contains(i) {
            if r.count == 1 { picked = nil }
            else if i == r.lowerBound { picked = (i + 1)...r.upperBound }
            else if i == r.upperBound { picked = r.lowerBound...(i - 1) }
            else { picked = r.lowerBound...i }
            return
        }
        let grown = min(i, r.lowerBound)...max(i, r.upperBound)
        let lines = allLines
        let characters = grown.reduce(0) { $0 + (lines.indices.contains($1) ? lines[$1].count : 0) }
        picked = grown.count <= Self.maxLines && characters <= Self.maxCharacters ? grown : i...i
    }

    /// A line while choosing: chosen lines are bright on a soft highlight, the rest step back.
    private func pickable(_ text: String, index: Int, size: CGFloat) -> some View {
        let on = picked?.contains(index) == true
        return Text(text.isEmpty ? "♪" : text)
            .font(.serif(size, weight: on ? .semibold : .regular))
            .foregroundStyle(.white.opacity(on ? 1 : 0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(on ? 0.14 : 0)))
            .contentShape(Rectangle())
            .onTapGesture { if !text.isEmpty { pick(index) } }
            .animation(.easeOut(duration: 0.18), value: on)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint("Double-tap to add or remove this line")
    }

    @ViewBuilder private var content: some View {
        if loading {
            Spacer(); ProgressView(); Spacer()
        } else if let lyrics, lyrics.isSynced {
            synced(lyrics)
        } else if selecting, lyrics?.plain != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(allLines.enumerated()), id: \.offset) { i, text in pickable(text, index: i, size: 24) }
                }
                .padding(.horizontal, 14).padding(.vertical, 24)
            }
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
                            Group {
                                if selecting { pickable(line.text, index: line.id, size: 28).padding(.horizontal, -10) }
                                else { lineView(line, state: active.map { line.id < $0 ? -1 : (line.id == $0 ? 0 : 1) } ?? 1) }
                            }
                            .id(line.id)
                        }
                        Color.clear.frame(height: 420)
                    }
                    .padding(.horizontal, 24)
                }
                .onChange(of: active) { _, now in
                    guard let now, !selecting else { return }
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
                if player.current != nil, !line.text.isEmpty {
                    Button("Share lyrics", systemImage: "square.and.arrow.up") { startSelecting(at: line.id) }
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
