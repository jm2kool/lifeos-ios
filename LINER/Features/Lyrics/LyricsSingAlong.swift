import SwiftUI

/// Sing-along: big bold lines down the screen, the one being sung about a third of the way down. Lines already
/// sung soften and blur a little, lines to come wait slightly blurred; background vocals sit smaller under
/// their line and a second voice is set on the right.
extension LyricsView {
    func singAlong(_ lyrics: Lyrics) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let t = now()
            let active = lyrics.activeIndex(at: t + 0.15)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 240)
                        ForEach(lyrics.lines) { line in
                            singAlongLine(line, phase: phase(of: line, active: active, time: t))
                                .padding(.top, line.isBackground ? 4 : 26)
                                .id(line.id)
                        }
                        Color.clear.frame(height: 460)
                    }
                    .padding(.horizontal, 26)
                }
                .scrollDisabled(false)
                .onScrollPhaseChange { _, new in if new == .interacting { touch() } }
                .onChange(of: active) { _, now in
                    guard let now else { return }
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { proxy.scrollTo(now, anchor: UnitPoint(x: 0.5, y: 0.32)) }
                }
                // Opening the lyrics lands straight on the line being sung, not the top of the song.
                .task(id: lyrics) {
                    let start = lyrics.activeIndex(at: now() + 0.15) ?? 0
                    proxy.scrollTo(start, anchor: UnitPoint(x: 0.5, y: 0.32))
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(start, anchor: UnitPoint(x: 0.5, y: 0.32))
                }
            }
        }
    }

    private func phase(of line: Lyrics.Line, active: Int?, time: Double) -> KaraokeLine.Phase {
        if line.isBackground { return time >= line.time - 0.1 && time < line.end + 0.5 ? .active : (time >= line.end ? .past : .future) }
        guard let active else { return .future }
        return line.id < active ? .past : (line.id == active ? .active : .future)
    }

    private func singAlongLine(_ line: Lyrics.Line, phase: KaraokeLine.Phase) -> some View {
        let size: CGFloat = line.isBackground ? 22 : 34
        let align: TextAlignment = line.voice == 1 ? .trailing : .leading
        return Group {
            if line.words.isEmpty {
                // An instrumental break: three dots that breathe while it lasts.
                Image(systemName: "ellipsis").font(.system(size: 30, weight: .bold))
                    .symbolEffect(.variableColor.iterative, isActive: phase == .active)
                    .foregroundStyle(.white.opacity(phase == .active ? 0.95 : 0.3))
            } else {
                KaraokeLine(line: line, phase: phase,
                            style: KaraokeStyle(font: lyricFont(size), size: size, alignment: align, textCase: face?.textCase), clock: now)
            }
        }
        .frame(maxWidth: .infinity, alignment: line.voice == 1 ? .trailing : .leading)
        .scaleEffect(phase == .active ? 1.0 : 0.96, anchor: line.voice == 1 ? .trailing : .leading)
        .blur(radius: phase == .active ? 0 : (phase == .past ? 1.6 : 0.8))
        .opacity(phase == .active ? 1 : (phase == .past ? 0.5 : 0.8))
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: phase)
        .contentShape(Rectangle())
        .onTapGesture { player.seek(to: line.time); touch() }
        .contextMenu {
            Button("Save line", systemImage: "bookmark") { save(line: line) }
            Button("Save as favourite moment", systemImage: "star") { saveMoment(line) }
            if !line.text.isEmpty { Button("Share lyrics", systemImage: "square.and.arrow.up") { startSelecting(at: line.id) } }
        }
        .accessibilityAddTraits(phase == .active ? .isSelected : [])
        .accessibilityHint("Double-tap to jump here")
    }

    // MARK: Saving

    func save(line: Lyrics.Line) {
        guard let item = player.current, !line.text.isEmpty else { return }
        let note = Store.shared.songNoteOrNew(for: item)
        if !note.lyricLines.contains(line.text) { note.lyricLines.append(line.text) }
        note.updatedAt = .now
        Store.shared.save()
        flash("Saved to Song Passport")
    }

    func saveMoment(_ line: Lyrics.Line) {
        guard let item = player.current else { return }
        let note = Store.shared.songNoteOrNew(for: item)
        note.moments.append(Moment(seconds: line.time, name: line.text))
        Store.shared.save()
        flash("Saved as a favourite moment")
    }

    // MARK: Sharing lines

    /// Every line's text, synced or plain, in order.
    var allLines: [String] {
        guard let lyrics else { return [] }
        if lyrics.isSynced { return lyrics.lines.map(\.text) }
        return (lyrics.plain ?? "").components(separatedBy: .newlines)
    }

    private var pickedText: [String] {
        guard let picked else { return [] }
        let lines = allLines
        return picked.compactMap { lines.indices.contains($0) ? lines[$0].trimmingCharacters(in: .whitespaces) : nil }.filter { !$0.isEmpty }
    }

    var shareBar: some View {
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

    var pickList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(allLines.enumerated()), id: \.offset) { i, text in pickable(text, index: i) }
            }
            .padding(.horizontal, 14).padding(.top, 90).padding(.bottom, 40)
        }
    }

    func startSelecting(at line: Int?) {
        picked = line.map { $0...$0 }
        selecting = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func stopSelecting() { selecting = false; picked = nil; touch() }

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
    private func pickable(_ text: String, index: Int) -> some View {
        let on = picked?.contains(index) == true
        return Text(text.isEmpty ? "♪" : text)
            .font(lyricFont(26))
            .foregroundStyle(.white.opacity(on ? 1 : 0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(on ? 0.16 : 0)))
            .contentShape(Rectangle())
            .onTapGesture { if !text.isEmpty { pick(index) } }
            .animation(.easeOut(duration: 0.18), value: on)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint("Double-tap to add or remove this line")
    }
}

/// The ••• in the lyrics: the look, timing nudges, listening for word timings (mixtapes), editing and sharing.
struct LyricsMenu: View {
    let view: LyricsView

    var body: some View {
        Menu {
            Picker("Look", selection: Binding(get: { view.style.rawValue }, set: { view.styleRaw = $0 })) {
                ForEach(LyricsStyle.allCases) { Label($0.label, systemImage: $0.symbol).tag($0.rawValue) }
            }
            Section("Timing \(view.nudge == 0 ? "" : String(format: "%+.1f s", view.nudge))") {
                Button("Words earlier", systemImage: "backward") { nudge(-0.1) }
                Button("Words later", systemImage: "forward") { nudge(0.1) }
                if view.nudge != 0 { Button("Reset timing", systemImage: "arrow.uturn.backward") { nudge(-view.nudge) } }
            }
            if case .local(let track) = view.player.current, let lyrics = view.lyrics, lyrics.isSynced {
                if SpeechAligner.aligned(view.player.current?.id ?? "") != nil {
                    Button("Forget heard timings", systemImage: "ear.trianglebadge.exclamationmark") { forget() }
                } else {
                    Button(view.listening ? "Listening…" : "Time words by listening", systemImage: "waveform.and.mic") { listen(track, lyrics) }
                        .disabled(view.listening)
                }
            }
            if view.lyrics != nil {
                Button("Edit Lyrics and Timings", systemImage: "pencil") { view.editing = true }
            }
            if !view.allLines.isEmpty {
                Button("Share lyrics", systemImage: "square.and.arrow.up") { view.startSelecting(at: nil) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Lyrics options")
    }

    private func nudge(_ by: Double) {
        guard let id = view.player.current?.id else { return }
        view.nudge = ((view.nudge + by) * 10).rounded() / 10
        LyricsNudge.set(view.nudge, for: id)
        view.touch()
    }

    private func listen(_ track: LocalTrack, _ lyrics: Lyrics) {
        guard let item = view.player.current else { return }
        view.listening = true
        view.flash("Listening to the song for word timings…")
        Task {
            let outcome = await SpeechAligner.align(itemID: item.id, audio: track.fileURL, lyrics: lyrics)
            view.listening = false
            switch outcome {
            case .done(let matched, let total):
                view.lyrics = await LyricsStore.lyrics(for: item)
                view.flash("Heard \(matched) of \(total) words")
            case .notEnough: view.flash("Couldn't hear enough words over the music")
            case .unavailable: view.flash("Listening isn't available for this song's language")
            }
        }
    }

    private func forget() {
        guard let item = view.player.current else { return }
        SpeechAligner.forget(item.id)
        Task { view.lyrics = await LyricsStore.lyrics(for: item) }
    }
}
