import SwiftUI
import SwiftData

struct FocusView: View {
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var timer
    @Environment(Router.self) private var router
    @State private var choosing = false
    @Namespace private var ns
    @Bindable private var shield = FocusShield.shared

    var body: some View {
        let subject = store.subject(timer.context.subjectID)
        let color = timer.phase.isBreak ? Theme.good : Color(hex: subject?.color ?? "#8FA8FF")
        ScrollView {
            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    dial(now: ctx.date, color: color)
                        .onChange(of: ctx.date) { _, d in timer.tick(now: d) }
                }
                contextCard(subject: subject, color: color)
                controls(color: color)
                if !timer.active { lengthPicker }
                if shield.available { shieldCard }
                StatsSection()
                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
        .backdrop([color, Theme.instinct])
        .navigationTitle("Focus")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .settings } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $choosing) {
            FocusContextPicker().presentationDetents([.medium, .large]).preferredColorScheme(.dark)
        }
    }

    private func dial(now: Date, color: Color) -> some View {
        let remaining = timer.remaining(at: now)
        return ZStack {
            Circle()
                .fill(Color.clear)
                .glassEffect(.regular.tint(color.opacity(0.18)), in: .circle)
            ProgressRing(progress: timer.active ? timer.progress(at: now) : 0, color: color, line: 12)
                .padding(18)
            VStack(spacing: 6) {
                Text(timer.waiting ? "Break over" : timer.phase.label.uppercased())
                    .font(.caption.weight(.heavy)).foregroundStyle(color)
                Text(Fmt.countdown(remaining))
                    .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: Int(remaining))
                if timer.active {
                    HStack(spacing: 6) {
                        ForEach(1...max(1, timer.rounds), id: \.self) { i in
                            Circle().fill(i < timer.round || (i == timer.round && timer.phase.isBreak) ? color : Color.white.opacity(0.18))
                                .frame(width: 7, height: 7)
                        }
                    }
                    Text("\(Int(timer.focused(at: now) / 60)) min focused").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 290, height: 290)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timer.phase.label), \(Int(remaining / 60)) minutes left")
    }

    private func contextCard(subject: StudySubject?, color: Color) -> some View {
        Button { if !timer.active { choosing = true } } label: {
            HStack(spacing: 12) {
                Image(systemName: subject?.icon ?? "scope").font(.title3).foregroundStyle(color).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.context.title).font(.headline).lineLimit(1)
                    Text(timer.context.goal.isEmpty ? (subject?.name ?? "Free focus — tap to link a block or assignment") : timer.context.goal)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !timer.active { Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary) }
            }
            .glassCard(tint: color, radius: 22, padding: 14, interactive: !timer.active)
        }
        .buttonStyle(.plain)
    }

    private func controls(color: Color) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if !timer.active {
                    Button { withAnimation(.spring(duration: 0.4)) { timer.start() } } label: {
                        Label("Start", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(color)
                    .glassEffectID("main", in: ns)
                } else {
                    if timer.waiting {
                        Button { withAnimation(.spring(duration: 0.4)) { timer.start() } } label: {
                            Label("Round \(timer.round)", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent).tint(color)
                        .glassEffectID("main", in: ns)
                    } else if timer.phase.isBreak {
                        Button { withAnimation(.spring(duration: 0.4)) { timer.skip() } } label: {
                            Label("Skip break", systemImage: "forward.fill").font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent).tint(Theme.good)
                        .glassEffectID("main", in: ns)
                    } else {
                        Button { withAnimation(.spring(duration: 0.4)) { timer.togglePause() } } label: {
                            Label(timer.running ? "Pause" : "Resume", systemImage: timer.running ? "pause.fill" : "play.fill")
                                .font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent).tint(color)
                        .glassEffectID("main", in: ns)
                        Button { withAnimation(.spring(duration: 0.4)) { timer.skip() } } label: {
                            Image(systemName: "forward.end.fill").frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("skip", in: ns)
                        .accessibilityLabel("End this round now")
                    }
                    Button { withAnimation(.spring(duration: 0.4)) { timer.finish() } } label: {
                        Image(systemName: "stop.fill").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("stop", in: ns)
                    .accessibilityLabel("Finish session")
                }
            }
            .controlSize(.extraLarge)
        }
        .sensoryFeedback(.impact, trigger: timer.active)
    }

    private var lengthPicker: some View {
        HStack {
            Text("Focus length").font(.subheadline)
            Spacer()
            Button { timer.setLength(minutes: max(5, Int(timer.phaseLength / 60) - 5)) } label: { Image(systemName: "minus") }
                .buttonStyle(.glass).buttonBorderShape(.circle)
            Text(Fmt.minutes(Int(timer.phaseLength / 60))).font(.subheadline.monospacedDigit().weight(.semibold)).frame(minWidth: 64)
            Button { timer.setLength(minutes: min(180, Int(timer.phaseLength / 60) + 5)) } label: { Image(systemName: "plus") }
                .buttonStyle(.glass).buttonBorderShape(.circle)
        }
        .glassCard(radius: 20, padding: 12)
    }

    private var shieldCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { shield.enabled && shield.authorized }, set: { on in
                if on && !shield.authorized { Task { await shield.authorize(); shield.enabled = shield.authorized } } else { shield.enabled = on }
            })) {
                Label("Block distracting apps", systemImage: "shield.lefthalf.filled")
            }
            #if canImport(FamilyControls)
            if shield.authorized && shield.enabled { ShieldPicker() }
            #endif
            if let p = shield.problem { Text(p).font(.caption).foregroundStyle(Theme.warn) }
        }
        .glassCard(radius: 20, padding: 14)
    }
}

/// Choose what this focus session is for.
struct FocusContextPicker: View {
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var timer
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StudyBlock> { !$0.trashed }, sort: \StudyBlock.startAt) private var blocks: [StudyBlock]
    @Query(filter: #Predicate<Assignment> { !$0.trashed }, sort: \Assignment.dueAt) private var assignments: [Assignment]

    var body: some View {
        let now = Date()
        let soon = blocks.filter { $0.status == .planned && $0.endAt > now && $0.startAt < now.addingTimeInterval(36 * 3600) }
        NavigationStack {
            List {
                Section {
                    Button { timer.context = .init(); dismiss() } label: { Label("Free focus", systemImage: "scope") }
                }
                .listRowBackground(Color.white.opacity(0.06))
                if !soon.isEmpty {
                    Section("Study blocks") {
                        ForEach(soon) { b in
                            Button { timer.prepare(block: b); dismiss() } label: {
                                VStack(alignment: .leading) {
                                    Text(store.find(Assignment.self, b.assignmentID)?.title ?? (b.goal.isEmpty ? b.kind.label : b.goal))
                                    Text("\(Fmt.dayTime(b.startAt)) · \(store.subject(b.subjectID)?.name ?? b.kind.label)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                Section("Assignments") {
                    ForEach(assignments.filter(\.isOpen)) { a in
                        Button { timer.prepare(assignment: a); dismiss() } label: {
                            VStack(alignment: .leading) {
                                Text(a.title)
                                Text("\(store.subject(a.subjectID)?.name ?? a.kind.label) · \(Fmt.due(a.dueAt))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .tint(.primary)
            .backdrop([Theme.accent])
            .navigationTitle("Focus on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// At the end of a session: how did it go? This is what Instinct replans from.
struct OutcomeSheet: View {
    let finished: FocusTimer.Finished
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var timer
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: Outcome = .done
    @State private var note = ""
    @Namespace private var ns

    var body: some View {
        let subject = store.subject(finished.context.subjectID)
        let color = Color(hex: subject?.color ?? "#8FA8FF")
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(finished.minutes) min").font(.largeTitle.weight(.bold)).monospacedDigit()
                        Text(finished.context.title).font(.headline)
                        if !finished.context.goal.isEmpty { Label(finished.context.goal, systemImage: "target").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Text(finished.context.blockID != nil ? "Did you finish what this block was for?" : "Did you get done what you meant to?")
                        .font(.subheadline)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(Outcome.allCases) { o in
                                Button {
                                    withAnimation(.snappy) { outcome = o }
                                    Haptics.select()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: o.symbol).font(.title2)
                                        Text(o.label).font(.caption.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(outcome == o ? .regular.tint(tint(o).opacity(0.55)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
                                .glassEffectID(o.rawValue, in: ns)
                            }
                        }
                    }
                    TextField("A note for Instinct (optional): what's left, what was hard…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
                .padding()
            }
            .backdrop([color])
            .navigationTitle("Session done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { timer.discard(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { timer.record(finished, outcome: outcome, note: note); dismiss() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func tint(_ o: Outcome) -> Color {
        switch o {
        case .done: return Theme.good
        case .partial: return Theme.warn
        case .notDone: return Theme.bad
        }
    }
}
