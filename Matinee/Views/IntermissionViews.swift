import SwiftUI

/// Floating glass bar above the tab bar while a film is in progress.
struct NowWatchingBar: View {
    let session: WatchSession
    @Environment(Watching.self) private var watching
    @Environment(Router.self) private var router

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let elapsed = session.elapsed(at: tl.date)
            let over = session.isProbablyOver(at: tl.date)
            HStack(spacing: 12) {
                Button { router.open(session.film) } label: {
                    HStack(spacing: 12) {
                        PosterView(film: session.film, width: 34, corner: 5, showTitleFallback: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.film.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(subtitle(elapsed: elapsed, over: over))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if session.running && !over {
                    iconButton("pause.fill", label: "Intermission") { router.sheet = .intermission(session.id) }
                } else if over {
                    iconButton("checkmark", label: "Log it") { finish() }
                } else {
                    iconButton("play.fill", label: "Resume") { watching.resume(session.id) }
                }
            }
            .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                if let p = session.progress(at: tl.date) {
                    GeometryReader { g in
                        Capsule().fill(Theme.accent).frame(width: max(4, g.size.width * p), height: 2.5)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 1)
                }
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16)
    }

    private func subtitle(elapsed: TimeInterval, over: Bool) -> String {
        if over { return "Credits rolling? Tap ✓ to log it" }
        let total = session.runtime.map { " of \(filmClock($0))" } ?? ""
        if session.running { return "Watching · \(filmClock(elapsed))\(total)" }
        let mood = session.lastStop.map { "\($0.mood) " } ?? ""
        return "\(mood)Intermission at \(filmClock(elapsed))\(total)"
    }

    private func finish() {
        let film = session.film
        watching.end(session.id)
        router.sheet = .log(film, nil)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.accent, in: .circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Pause a film: confirm where you are, pick a mood, leave yourself a note.
struct IntermissionSheet: View {
    let sessionID: UUID
    @Environment(Watching.self) private var watching
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var position: Double = 0
    @State private var mood = "🤔"
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private var session: WatchSession? { watching.sessions.first { $0.id == sessionID } }

    var body: some View {
        NavigationStack {
            if let s = session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 14) {
                            PosterView(film: s.film, width: 64, corner: 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("INTERMISSION").font(.caption.weight(.heavy)).tracking(1.4).foregroundStyle(Theme.accent)
                                Text(s.film.title).font(.title3.weight(.bold)).lineLimit(2)
                                Text("Started \(s.started.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(Theme.dim)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            label("You stopped at")
                            HStack(alignment: .firstTextBaseline) {
                                Text(filmClock(position)).font(.system(size: 44, weight: .bold, design: .rounded)).contentTransition(.numericText())
                                if let r = s.runtime { Text("of \(filmClock(r))").foregroundStyle(Theme.dim) }
                            }
                            if let r = s.runtime {
                                Slider(value: $position, in: 0...r, step: 60).tint(Theme.accent)
                            } else {
                                Stepper("Adjust", value: $position, in: 0...(6 * 3600), step: 60).labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            label("How's it going?")
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Mood.all, id: \.emoji) { m in
                                        Button { mood = m.emoji; UISelectionFeedbackGenerator().selectionChanged() } label: {
                                            VStack(spacing: 4) {
                                                Text(m.emoji).font(.system(size: 30))
                                                Text(m.label).font(.caption2.weight(.semibold)).foregroundStyle(mood == m.emoji ? .white : Theme.dim)
                                            }
                                            .frame(width: 74, height: 74)
                                            .background(mood == m.emoji ? Theme.accent.opacity(0.35) : Theme.card, in: .rect(cornerRadius: 18))
                                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(mood == m.emoji ? Theme.accent : .clear, lineWidth: 1.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            label("Where were you?")
                            TextField("e.g. right after the heist", text: $note, axis: .vertical)
                                .lineLimit(1...4)
                                .focused($noteFocused)
                                .padding(14)
                                .background(Theme.card, in: .rect(cornerRadius: 16))
                            Text("Future you will thank you when you come back to it.").font(.caption).foregroundStyle(Theme.dim)
                        }

                        if !s.stops.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                label("Earlier stops")
                                ForEach(s.stops.reversed()) { stop in IntermissionRow(stop: stop) }
                            }
                        }

                        VStack(spacing: 10) {
                            Button { pause() } label: { Label("Pause here", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.glassProminent).controlSize(.large)
                            Button {
                                let film = s.film
                                watching.end(s.id)
                                router.sheet = .log(film, nil)
                            } label: { Label("I finished it — log it", systemImage: "checkmark").frame(maxWidth: .infinity) }
                                .buttonStyle(.glass).controlSize(.large)
                            Button("Stop tracking this film", role: .destructive) { watching.end(s.id); dismiss() }
                                .font(.footnote.weight(.semibold))
                                .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .oledBackground()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Keep watching", systemImage: "xmark") { dismiss() } } }
                .onAppear {
                    position = (s.elapsed() / 60).rounded(.down) * 60
                    if let r = s.runtime { position = min(position, r) }
                    mood = s.lastStop?.mood ?? "🤔"
                }
            } else {
                EmptyState(symbol: "film", title: "Nothing playing", message: "Start watching a film from its page.")
                    .oledBackground()
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
    }

    private func pause() {
        watching.intermission(sessionID, at: position, mood: mood, note: note)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

struct IntermissionRow: View {
    let stop: Intermission
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(stop.mood).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(filmClock(stop.at)) · \(Mood.label(stop.mood))").font(.subheadline.weight(.semibold))
                if !stop.note.isEmpty { Text("“\(stop.note)”").font(.subheadline).foregroundStyle(.white.opacity(0.8)) }
                Text(stop.when.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 14))
    }
}

/// Home shelf of films you paused, each with your note so you remember where you were.
struct IntermissionShelf: View {
    @Environment(Watching.self) private var watching
    @Environment(Router.self) private var router

    var body: some View {
        let paused = watching.paused
        if !paused.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Intermission", subtitle: "Pick up where you left off")
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(paused) { s in card(s) }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private func card(_ s: WatchSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { router.open(s.film) } label: { PosterView(film: s.film, width: 74, corner: 8) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                Text(s.film.title).font(.headline).lineLimit(1)
                Text("Stopped at \(filmClock(s.banked))\(s.runtime.map { " of \(filmClock($0))" } ?? "")")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                if let stop = s.lastStop {
                    Text("\(stop.mood) \(stop.note.isEmpty ? Mood.label(stop.mood) : "“\(stop.note)”")")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                    Text(stop.when.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                if let p = s.progress() { ProgressView(value: p).tint(Theme.accent) }
                GlassChip(prominent: true, action: { watching.resume(s.id) }) {
                    Label("Resume", systemImage: "play.fill")
                }
            }
        }
        .padding(12)
        .frame(width: 300, height: 190, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 22))
    }
}
