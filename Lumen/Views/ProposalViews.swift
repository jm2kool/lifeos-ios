import SwiftUI
import SwiftData

/// Instinct's (or the auto-planner's) suggested plan, waiting on Today: Accept, Edit or Reject.
struct ProposalCard: View {
    @Bindable var proposal: Proposal
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @State private var rejecting = false
    @State private var feedback = ""
    @Namespace private var ns

    var body: some View {
        let drafts = proposal.drafts.sorted { $0.startAt < $1.startAt }
        let minutes = drafts.reduce(0) { $0 + $1.minutes }
        let days = Set(drafts.map { Calendar.current.startOfDay(for: $0.startAt) }).count
        let fromInstinct = proposal.createdBy == Actor.instinct.rawValue
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if fromInstinct { InstinctBadge() } else { Label("Auto-planner", systemImage: "wand.and.stars").font(.caption.weight(.semibold)) }
                Spacer()
                Text(proposal.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
            }
            Text(fromInstinct ? "Instinct has a new plan" : "Here's a plan").font(.title3.weight(.bold))
            Text("\(drafts.count) blocks · \(Fmt.minutes(minutes)) over \(days) day\(days == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if !proposal.reasoning.isEmpty {
                Text(proposal.reasoning).font(.subheadline).lineLimit(4)
            }
            VStack(spacing: 6) {
                ForEach(drafts.prefix(3)) { d in DraftLine(draft: d) }
                if drafts.count > 3 {
                    Text("+ \(drafts.count - 3) more").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(proposal.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warn)
            }
            if rejecting {
                TextField("What should change? (optional, Instinct reads this)", text: $feedback, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if rejecting {
                        Button("Cancel") { withAnimation(.snappy) { rejecting = false } }
                            .buttonStyle(.glass)
                            .glassEffectID("edit", in: ns)
                        Button("Send & reject", role: .destructive) {
                            store.reject(proposal, feedback: feedback.isEmpty ? nil : feedback)
                            Haptics.warning()
                        }
                        .buttonStyle(.glassProminent).tint(Theme.bad)
                        .frame(maxWidth: .infinity)
                        .glassEffectID("accept", in: ns)
                    } else {
                        Button {
                            withAnimation(.spring(duration: 0.45)) { store.accept(proposal) }
                        } label: { Label("Accept", systemImage: "checkmark").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                            .glassEffectID("accept", in: ns)
                        Button("Edit") { router.sheet = .proposal(proposal.id) }
                            .buttonStyle(.glass)
                            .glassEffectID("edit", in: ns)
                        Button("Reject") { withAnimation(.snappy) { rejecting = true } }
                            .buttonStyle(.glass)
                            .glassEffectID("reject", in: ns)
                    }
                }
                .controlSize(.large)
            }
        }
        .glassCard(tint: fromInstinct ? Theme.instinct : Theme.accent, radius: 28, padding: 18)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

struct DraftLine: View {
    var draft: PlanDraft
    @Environment(Store.self) private var store
    var body: some View {
        let s = store.subject(draft.subjectID)
        let title = store.find(Assignment.self, draft.assignmentID)?.title ?? (draft.goal.isEmpty ? (BlockKind(rawValue: draft.kind)?.label ?? "Study") : draft.goal)
        HStack(spacing: 8) {
            SubjectDot(color: Color(hex: s?.color ?? "#8FA8FF"))
            Text(Fmt.day(draft.startAt)).font(.caption.weight(.semibold)).frame(width: 74, alignment: .leading)
            Text(Fmt.span(draft.startAt, draft.endAt)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(title).font(.caption).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// The whole proposal, editable: change times, drop blocks, then accept.
struct ProposalSheet: View {
    @Bindable var proposal: Proposal
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [PlanDraft] = []
    @State private var loaded = false
    @State private var conflicts: Set<UUID> = []

    var body: some View {
        List {
            if !proposal.reasoning.isEmpty {
                Section("Why") {
                    Text(proposal.reasoning).font(.subheadline)
                    ForEach(proposal.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn).font(.caption) }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            ForEach(groupedDays, id: \.self) { day in
                Section(Fmt.day(day)) {
                    ForEach(dayDrafts(day)) { d in
                        DraftEditorRow(draft: binding(d.id), conflict: conflicts.contains(d.id))
                    }
                    .onDelete { idx in delete(idx, on: day) }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            if drafts.isEmpty {
                Text("No blocks left in this plan.").foregroundStyle(.secondary).listRowBackground(Color.white.opacity(0.06))
            }
        }
        .backdrop([Theme.instinct])
        .navigationTitle(proposal.createdBy == Actor.instinct.rawValue ? "Instinct's plan" : "Suggested plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Accept") {
                    let edited = drafts != proposal.drafts
                    store.accept(proposal, drafts: edited ? drafts : nil)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(!proposal.isPending)
            }
        }
        .onAppear {
            guard !loaded else { return }
            drafts = proposal.drafts.sorted { $0.startAt < $1.startAt }
            loaded = true
            checkConflicts()
        }
        .onChange(of: drafts) { _, _ in checkConflicts() }
    }

    private var groupedDays: [Date] {
        Array(Set(drafts.map { Calendar.current.startOfDay(for: $0.startAt) })).sorted()
    }

    private func dayDrafts(_ day: Date) -> [PlanDraft] {
        drafts.filter { Calendar.current.isDate($0.startAt, inSameDayAs: day) }
    }

    private func binding(_ id: UUID) -> Binding<PlanDraft> {
        Binding(get: { drafts.first { $0.id == id } ?? PlanDraft(startAt: Date(), endAt: Date()) },
                set: { new in if let i = drafts.firstIndex(where: { $0.id == id }) { drafts[i] = new } })
    }

    private func delete(_ idx: IndexSet, on day: Date) {
        let onDay = dayDrafts(day)
        let ids = Set(idx.map { onDay[$0].id })
        withAnimation { drafts.removeAll { ids.contains($0.id) } }
    }

    /// Flags blocks that clash with a busy time or with each other after editing.
    private func checkConflicts() {
        let busy = store.live(BusySlot.self)
        var out: Set<UUID> = []
        for d in drafts {
            if busy.contains(where: { $0.startAt < d.endAt && $0.endAt > d.startAt }) { out.insert(d.id) }
            if drafts.contains(where: { $0.id != d.id && $0.startAt < d.endAt && $0.endAt > d.startAt }) { out.insert(d.id) }
        }
        conflicts = out
    }
}

struct DraftEditorRow: View {
    @Binding var draft: PlanDraft
    var conflict: Bool
    @Environment(Store.self) private var store

    var body: some View {
        let s = store.subject(draft.subjectID)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SubjectDot(color: Color(hex: s?.color ?? "#8FA8FF"))
                Text(store.find(Assignment.self, draft.assignmentID)?.title ?? (draft.goal.isEmpty ? (BlockKind(rawValue: draft.kind)?.label ?? "Study") : draft.goal))
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if conflict { Label("Clash", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.bad) }
            }
            HStack {
                DatePicker("Start", selection: Binding(get: { draft.startAt }, set: { new in
                    let len = draft.endAt.timeIntervalSince(draft.startAt)
                    draft.startAt = new
                    draft.endAt = new.addingTimeInterval(len)
                }), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                Text("for").foregroundStyle(.secondary)
                Stepper(Fmt.minutes(draft.minutes), value: Binding(get: { draft.minutes }, set: {
                    draft.endAt = draft.startAt.addingTimeInterval(TimeInterval(max(10, $0) * 60))
                }), in: 10...240, step: 5)
                .font(.caption)
            }
            if !draft.goal.isEmpty { Text(draft.goal).font(.caption).foregroundStyle(.secondary) }
            if let r = draft.reason, !r.isEmpty { Label(r, systemImage: "sparkle").font(.caption2).foregroundStyle(Theme.instinct) }
        }
        .padding(.vertical, 4)
    }
}
