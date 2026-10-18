import SwiftUI
import UIKit

enum LibraryPage: Hashable {
    case board, drafts, draft(String), calendar, timetable, feed, saved, finances, workflows
    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .board: BoardView()
        case .drafts: DraftsView()
        case .draft(let id): DraftDetail(id: id)
        case .calendar: CalendarView()
        case .timetable: TimetableView()
        case .feed: FeedView()
        case .saved: SavedView()
        case .finances: FinancesView()
        case .workflows: WorkflowsView()
        }
    }
}

struct LibraryView: View {
    @Environment(Store.self) private var store
    var body: some View {
        List {
            Section {
                link(.board, "Board", "rectangle.split.3x1.fill", .green, badge: store.cards.filter { $0.column < 2 }.count)
                link(.drafts, "Drafts", "doc.text.fill", .pink, badge: store.pendingDrafts.count)
                link(.calendar, "Calendar", "calendar", .red)
                link(.timetable, "Timetable", "clock.fill", .blue)
                link(.feed, "Feed", "dot.radiowaves.up.forward", .orange)
                link(.saved, "Saved", "bookmark.fill", .yellow)
                link(.finances, "Finances", "creditcard.fill", .teal)
                link(.workflows, "Workflows", "bolt.fill", .indigo)
            }
            Section("Assistant") {
                Button { store.sheet = .ask("") } label: { row("Ask Gemini", "sparkles", .purple, sub: "Move things around, plan, draft emails") }
                Button { store.sheet = .capture } label: { row("Capture", "plus", .green, sub: "Type or dictate; it gets sorted") }
                Button { store.sheet = .focus } label: { row("Focus session", "timer", .orange, sub: "Logs to your streak") }
                Button { store.sheet = .delegate("Hey \(store.assistantName), from LifeOS: ") } label: { row("Message \(store.assistantName)", "message.fill", .blue, sub: store.assistantAddress.isEmpty ? "Add their iMessage address in Settings" : store.assistantAddress) }
            }
            .buttonStyle(.plain)
            Section {
                Button { store.sheet = .activity } label: { row("Activity", "clock.arrow.circlepath", .gray, sub: "Every change and who made it") }
                Button { store.sheet = .settings } label: { row("Settings", "gearshape.fill", .gray, sub: store.syncStatus) }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Library")
        .pageBackground()
        .navigationDestination(for: LibraryPage.self) { $0.view }
    }
    private func link(_ p: LibraryPage, _ title: String, _ symbol: String, _ color: Color, badge: Int = 0) -> some View {
        NavigationLink(value: p) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: color)
                Text(title)
                Spacer()
                if badge > 0 { Text("\(badge)").foregroundStyle(.secondary) }
            }
        }
    }
    private func row(_ title: String, _ symbol: String, _ color: Color, sub: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) { Text(title); Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
        }
        .contentShape(.rect)
    }
}

// MARK: Board
struct BoardView: View {
    @Environment(Store.self) private var store
    @State private var column = 0
    @State private var newCard = ""
    @State private var dueCard: Card?
    @FocusState private var typing: Bool

    var body: some View {
        List {
            Section {
                Picker("Column", selection: $column) {
                    ForEach(0..<3) { i in Text("\(Reducer.columns[i]) \(store.cards(in: i).count)").tag(i) }
                }
                .pickerStyle(.segmented).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                HStack {
                    TextField("Add to \(Reducer.columns[column])", text: $newCard).focused($typing).submitLabel(.done).onSubmit(add)
                    if !newCard.isEmpty { Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) } }
                }
                ForEach(store.cards(in: column)) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.title).font(.body.weight(.medium))
                        if let d = c.due { Text(store.dueText(d)).font(.footnote.weight(.medium)).foregroundStyle(dueColor(c)) }
                        if c.unfiled { Text("Captured, not sorted yet").font(.caption).foregroundStyle(.secondary) }
                        if !c.note.isEmpty { Text(c.note).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 2)
                    .overlay(alignment: .leading) { if store.dueState(c.due, column: c.column) != .none { Capsule().fill(dueColor(c)).frame(width: 3).offset(x: -12) } }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if column < 2 {
                            Button("Move to \(Reducer.columns[column + 1])", systemImage: "arrow.right") { store.act(["op": "board.move", "id": .string(c.id), "column": .string(Reducer.columns[column + 1])], undo: "Moved to \(Reducer.columns[column + 1])") }.tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { store.act(["op": "board.remove", "id": .string(c.id), "title": .string(c.title)], undo: "Card deleted") }
                    }
                    .contextMenu {
                        ForEach(0..<3) { i in if i != c.column { Button("Move to \(Reducer.columns[i])", systemImage: i == 2 ? "checkmark" : "arrow.right") { store.act(["op": "board.move", "id": .string(c.id), "column": .string(Reducer.columns[i])], undo: "Moved") } } }
                        Button(c.due == nil ? "Set due date" : "Change due date", systemImage: "calendar") { dueCard = c }
                        Button("Send to \(store.assistantName)", systemImage: "message") { store.sheet = .delegate("From LifeOS (board card \(c.id)):\n\(c.title)\n\nWhat I want done: ") }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { store.act(["op": "board.remove", "id": .string(c.id)], undo: "Card deleted") }
                    }
                }
            } footer: {
                Text("Swipe right to move a card along. Long-press for due dates and more.")
            }
        }
        .navigationTitle("Board")
        .pageBackground()
        .sheet(item: $dueCard) { c in DueDateSheet(card: c).presentationDetents([.height(320)]) }
    }
    private func add() {
        let t = newCard.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        store.act(["op": "board.add", "title": .string(t), "column": .string(Reducer.columns[column])]); newCard = ""; typing = true
    }
    private func dueColor(_ c: Card) -> Color {
        switch store.dueState(c.due, column: c.column) { case .overdue: return .red; case .soon: return .orange; case .later: return .green; case .none: return .secondary }
    }
}

struct DueDateSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Due", selection: $date, displayedComponents: .date).datePickerStyle(.compact)
                Text("Today or overdue shows red, the next two days orange, later green.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Due date").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { store.act(["op": "board.update", "id": .string(card.id), "due": ""]); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.act(["op": "board.update", "id": .string(card.id), "due": .string(store.dayKey(date))]); dismiss() } }
            }
            .onAppear { if let d = card.due { date = store.date(d, minutes: 720) } }
        }
    }
}

// MARK: Drafts
struct DraftsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        List {
            if store.drafts.isEmpty { ContentUnavailableView("No drafts", systemImage: "doc.text", description: Text("Plans and email replies prepared for you show up here.")) }
            ForEach(store.drafts) { d in
                NavigationLink(value: LibraryPage.draft(d.id)) {
                    let v = d.latest?.version ?? 1
                    let n = d.parts.filter { store.review(d, v, $0.id) != nil }.count
                    HStack(spacing: 12) {
                        IconTile(symbol: d.isEmail ? "envelope.fill" : "doc.text.fill", color: n == d.parts.count ? .green : (d.isEmail ? .blue : .pink))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).font(.body.weight(.medium)).lineLimit(2)
                            Text(d.isEmail ? (n > 0 ? "Approved" : "Email draft · v\(v)") : "\(n) of \(d.parts.count) weeks approved · v\(v)").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions { if d.isEmail { Button("Delete", systemImage: "trash", role: .destructive) { store.act(["op": "draft.remove", "id": .string(d.id)], undo: "Draft deleted") } } }
            }
        }
        .navigationTitle("Drafts")
        .pageBackground()
    }
}

struct DraftDetail: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.openURL) private var openURL
    let id: String
    @State private var week = ""
    @State private var reviewed = false
    @State private var changes = ""
    @State private var body_ = ""
    @State private var editing = false

    var body: some View {
        if let d = store.drafts.first(where: { $0.id == id }), let v = d.latest {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if d.isEmail { email(d, v) } else { plan(d, v) }
                    review(d, v)
                }
                .padding(UI.gutter)
            }
            .pageBackground()
            .navigationTitle(d.title).navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if week.isEmpty { week = (d.parts.first { store.review(d, v.version, $0.id) == nil } ?? d.parts.first)?.id ?? "" }
                body_ = v.body
            }
        } else {
            ContentUnavailableView("Draft not found", systemImage: "doc.text")
        }
    }

    @ViewBuilder private func email(_ d: Draft, _ v: DraftVersion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([("To", v.to), ("From", v.from), ("CC", v.cc), ("Subject", v.subject)].filter { !$0.1.isEmpty }, id: \.0) { k, x in
                HStack(alignment: .top) { Text(k).foregroundStyle(.secondary).frame(width: 64, alignment: .leading); Text(x).textSelection(.enabled) }
                    .font(.subheadline).padding(.vertical, 8)
                Divider()
            }
            if editing {
                TextEditor(text: $body_).frame(minHeight: 240).scrollContentBackground(.hidden).padding(.top, 8)
            } else {
                Text(v.body).font(.body).textSelection(.enabled).padding(.top, 12)
            }
            if !v.by.isEmpty { Text("Written by \(v.by) · version \(v.version)").font(.caption).foregroundStyle(.tertiary).padding(.top, 10) }
        }
        .card()
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                Button {
                    var c = URLComponents(); c.scheme = "mailto"; c.path = v.to
                    c.queryItems = [URLQueryItem(name: "subject", value: v.subject), URLQueryItem(name: "body", value: v.body)]
                    if let u = c.url { openURL(u) }
                } label: { Label("Open in Mail", systemImage: "envelope").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).controlSize(.large)
                HStack(spacing: 10) {
                    Button { if editing { store.act(["op": "draft.email", "id": .string(d.id), "body": .string(body_), "by": "you"], undo: "Draft updated") }; editing.toggle() } label: {
                        Label(editing ? "Save" : "Edit", systemImage: editing ? "checkmark" : "pencil").frame(maxWidth: .infinity)
                    }
                    Button { UIPasteboard.general.string = v.body; store.show("Copied") } label: { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                    Button { store.sheet = .ask("Rewrite the email draft \(d.id) to be ") } label: { Label("Rewrite", systemImage: "sparkles").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.glass).controlSize(.large)
            }
        }
        Text("Nothing is sent from LifeOS. Mail opens with this text so you can check it and send it yourself.").font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func plan(_ d: Draft, _ v: DraftVersion) -> some View {
        if !v.intro.isEmpty { Text(v.intro.replacingOccurrences(of: "# ", with: "")).font(.subheadline).card() }
        ForEach(v.weeks) { w in
            DisclosureGroup {
                ForEach(Array(w.days.enumerated()), id: \.offset) { _, day in
                    DisclosureGroup(day.title) {
                        VStack(alignment: .leading, spacing: 0) {
                            if !day.subtitle.isEmpty { Text(day.subtitle).font(.caption).foregroundStyle(.secondary).padding(.bottom, 4) }
                            ForEach(Array(day.lines.enumerated()), id: \.offset) { _, l in Text(l).font(.footnote).padding(.vertical, 6); Divider() }
                        }
                    }
                    .font(.subheadline).padding(.vertical, 2)
                }
            } label: {
                HStack { Text(w.title).font(.body.weight(.semibold)); Spacer(); if store.review(d, v.version, w.id) != nil { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) } }
            }
            .card()
        }
        if !v.scope.isEmpty { DisclosureGroup("Full scope and source notes") { Text(v.scope).font(.caption.monospaced()).foregroundStyle(.secondary).padding(.top, 6) }.card() }
        if !v.questions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm when you approve").font(.headline)
                Text("Approving accepts these. Use Request changes to correct any.").font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(v.questions.enumerated()), id: \.offset) { i, q in
                    HStack(alignment: .top, spacing: 8) { Text("\(i + 1).").font(.footnote.weight(.semibold)).foregroundStyle(.secondary); Text(q).font(.footnote) }
                }
            }
            .card()
        }
    }

    @ViewBuilder private func review(_ d: Draft, _ v: DraftVersion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your review").font(.headline)
            if !d.isEmail {
                Picker("Week", selection: $week) { ForEach(d.parts) { w in Text(w.title + (store.review(d, v.version, w.id) != nil ? " ✓" : "")).tag(w.id) } }
                    .pickerStyle(.menu)
            }
            Toggle(d.isEmail ? "I checked the recipient and the text" : "I reviewed this week and accept the assumptions", isOn: $reviewed).font(.subheadline)
            TextField("Changes you want (optional)", text: $changes, axis: .vertical).lineLimit(3...6).padding(10)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
            HStack {
                Button("Approve", systemImage: "checkmark") { submit(d, v, "approve") }.buttonStyle(.glassProminent).disabled(!reviewed)
                Button("Request changes") { submit(d, v, "changes") }.buttonStyle(.glass).disabled(changes.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Your review is saved in LifeOS, where \(store.assistantName) picks it up. You can also message it.").font(.caption).foregroundStyle(.secondary)
        }
        .card()
        let hist = store.state["draftReviews"].object.values.filter { $0["draftId"].str == d.id }.sorted { ($0["at"].double ?? 0) > ($1["at"].double ?? 0) }
        if !hist.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("History").font(.headline)
                ForEach(hist, id: \.self) { r in
                    Label((r["action"].str == "approve" ? "Approved " : "Changes requested: ") + (d.parts.first { $0.id == r["week"].str }?.title ?? r["week"].str) + " · " + store.ago(r["at"].double ?? 0),
                          systemImage: r["action"].str == "approve" ? "checkmark.seal" : "pencil").font(.footnote)
                }
            }
            .card()
        }
    }
    private func submit(_ d: Draft, _ v: DraftVersion, _ action: String) {
        let w = d.isEmail ? "email-draft" : week
        store.act(["op": "draft.review", "draftId": .string(d.id), "version": JSON(v.version), "week": .string(w), "action": .string(action), "changes": .string(changes), "title": .string(d.title)], undo: action == "approve" ? "Approved" : "Changes recorded")
        let wt = d.parts.first { $0.id == w }?.title ?? w
        let text = "LifeOS draft review\n\(d.title) v\(v.version) · \(wt)\n" + (action == "approve" ? "APPROVED. I accept the listed assumptions." : "CHANGES REQUESTED:\n" + changes)
        changes = ""; reviewed = false
        if !store.assistantAddress.isEmpty { store.sheet = .delegate(text) }
    }
}
