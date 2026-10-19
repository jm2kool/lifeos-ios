import SwiftUI
import UIKit
import MessageUI

enum LibraryPage: Hashable {
    case board, drafts, draft(String), calendar, timetable, feed, saved, finances, workflows, today, inbox, study, captures
    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .today: TodayView()
        case .inbox: InboxView()
        case .study: StudyView()
        case .captures: CapturesView()
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
                ForEach(store.moreTabs, id: \.self) { t in
                    if let p = t.page { link(p, t.title, t.tile.0, t.tile.1, badge: store.badge(for: t), dot: store.reviewDot(for: t)) }
                }
                if !store.content["captures"].array.isEmpty {
                    link(.captures, "Captured", "mic.fill", .purple, dot: !store.capturesToReview.isEmpty)
                }
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
                NavigationLink { TabBarSettings() } label: { row("Tab bar", "dock.rectangle", .gray, sub: "Choose what sits in the bar") }
                Button { store.sheet = .settings } label: { row("Settings", "gearshape.fill", .gray, sub: store.syncStatus) }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("More")
        .pageBackground()
        .navigationDestination(for: LibraryPage.self) { $0.view }
    }
    private func link(_ p: LibraryPage, _ title: String, _ symbol: String, _ color: Color, badge: Int = 0, dot: Bool = false) -> some View {
        NavigationLink(value: p) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: color)
                Text(title)
                Spacer()
                if dot { ReviewDot() } else if badge > 0 { Text("\(badge)").foregroundStyle(.secondary) }
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
                        Spacer(minLength: 0)
                        if store.pendingDrafts.contains(where: { $0.id == d.id }) { ReviewDot() }
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
    @State private var confirmSend = false
    @State private var composing = false
    @State private var needEmail = false

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
        let handed = store.review(d, v.version, "email-draft")?["state"].str.hasPrefix("sent to") == true
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                Button {
                    if store.assistantEmail.isEmpty { needEmail = true } else { confirmSend = true }
                } label: { Label(handed ? "Sent to \(store.assistantName) · Send again" : "Send via \(store.assistantName)", systemImage: "paperplane.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).controlSize(.large).disabled(editing)
                HStack(spacing: 10) {
                    Button { if editing { store.act(["op": "draft.email", "id": .string(d.id), "body": .string(body_), "by": "you"], undo: "Draft updated") }; editing.toggle() } label: {
                        Label(editing ? "Save" : "Edit", systemImage: editing ? "checkmark" : "pencil").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    Button { UIPasteboard.general.string = v.body; store.show("Copied") } label: { Label("Copy", systemImage: "doc.on.doc").lineLimit(1).frame(maxWidth: .infinity) }
                    Button { store.sheet = .ask("Rewrite the email draft \(d.id) to be ") } label: { Label("Rewrite", systemImage: "sparkles").lineLimit(1).frame(maxWidth: .infinity) }
                }
                .buttonStyle(.glass).controlSize(.large)
                Button {
                    var c = URLComponents(); c.scheme = "mailto"; c.path = v.to
                    c.queryItems = [URLQueryItem(name: "subject", value: v.subject), URLQueryItem(name: "body", value: v.body)]
                    if let u = c.url { openURL(u) }
                } label: { Label("Open in Mail and send it myself", systemImage: "envelope").frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
            }
        }
        Text("Send via \(store.assistantName) emails \(store.assistantName) everything needed to send this reply for you, in the original thread. You confirm in the email screen before anything goes.")
            .font(.caption).foregroundStyle(.secondary)
            .confirmationDialog("Send this reply through \(store.assistantName)?", isPresented: $confirmSend, titleVisibility: .visible) {
                Button("Email \(store.assistantName) to send it") { startSend(d, v) }
            } message: {
                Text("\(store.assistantName) will send it to \(v.to.isEmpty ? "the sender" : v.to)\(v.from.isEmpty ? "" : " from " + v.from), exactly as written.")
            }
            .alert("Add \(store.assistantName)'s email", isPresented: $needEmail) {
                Button("Open Settings") { store.sheet = .settings }
                Button("Cancel", role: .cancel) {}
            } message: { Text("LifeOS needs \(store.assistantName)'s email address (Settings › Your iMessage assistant) to hand replies over.") }
            .sheet(isPresented: $composing) {
                let req = sendRequest(d, v)
                MailComposer(to: [store.assistantEmail], subject: req.subject, body: req.body) { result in
                    composing = false
                    if result == .sent { handedOver(d, v, how: "sent to \(store.assistantName)") }
                    else if result == .failed { store.show("Mail couldn't send that. Try again.") }
                }
                .ignoresSafeArea()
            }
    }

    private func startSend(_ d: Draft, _ v: DraftVersion) {
        if MailComposer.available { composing = true; return }
        // no Mail account on this iPhone: fall back to whatever mail app handles mailto
        let req = sendRequest(d, v)
        var c = URLComponents(); c.scheme = "mailto"; c.path = store.assistantEmail
        c.queryItems = [URLQueryItem(name: "subject", value: req.subject), URLQueryItem(name: "body", value: req.body)]
        guard let u = c.url else { store.show("Couldn't build the email"); return }
        openURL(u)
        handedOver(d, v, how: "sent to \(store.assistantName) (mail app)")
    }
    /// Records that you approved this version and handed it to your assistant to send.
    private func handedOver(_ d: Draft, _ v: DraftVersion, how: String) {
        store.act(["op": "draft.review", "draftId": .string(d.id), "version": JSON(v.version), "week": "email-draft", "action": "approve", "state": .string(how), "title": .string(d.title)], undo: "Handed to \(store.assistantName)")
        store.show("Sent to \(store.assistantName) to send")
    }
    /// The email your assistant gets: what to send, where, and the original message to reply to.
    private func sendRequest(_ d: Draft, _ v: DraftVersion) -> (subject: String, body: String) {
        let name = store.assistantName, me = store.profileName.isEmpty ? "me" : store.profileName
        let original = store.mail.first { $0.id == d.inboxId }
        let account = v.from.isEmpty ? (original?.account ?? "") : v.from
        var lines: [String] = [
            "Hi \(name),", "",
            "Please send this email reply for \(me) exactly as written below. Don't change the wording.",
            account.isEmpty ? "Reply in the existing thread of the original email." : "Send it from the \(account) account, as a reply in the existing thread of the original email.",
            "When it's sent, mark the email done in LifeOS\(d.inboxId.isEmpty ? "" : " (inbox.done, id \(d.inboxId))") and message \(me). If anything is unclear (for example you can't find the recipient's address), don't send; ask \(me) first.",
            "", "===== SEND THIS =====",
            "From account: " + (account.isEmpty ? "(the account the original email came to)" : account),
            "To: " + (v.to.isEmpty ? (original?.sender ?? "") : v.to),
        ]
        if !v.cc.isEmpty { lines.append("Cc: " + v.cc) }
        lines += ["Subject: " + v.subject, "", v.body, "===== END =====", ""]
        if let m = original {
            lines += ["Original email to reply to:", "From: " + m.sender, "Account: " + m.account, "Subject: " + m.title]
            if !m.checkedAt.isEmpty { lines.append("Received/checked: " + m.checkedAt) }
            if !m.url.isEmpty { lines.append("Link: " + m.url) }
            if !m.key.isEmpty { lines.append("Message key: " + m.key) }
            if !m.gist.isEmpty { lines.append("Summary: " + m.gist) }
            lines.append("")
        }
        let ref: JSON = ["draftId": .string(d.id), "version": JSON(v.version), "inboxId": .string(d.inboxId), "from": .string(account), "to": .string(v.to), "cc": .string(v.cc),
                         "subject": .string(v.subject), "body": .string(v.body), "threadUrl": .string(original?.url ?? ""), "messageKey": .string(original?.key ?? "")]
        lines += ["Approved by \(me) in LifeOS on \(Date().formatted(date: .abbreviated, time: .shortened)).", "", "LIFEOS-SEND " + ref.text()]
        return ("Please send: " + v.subject + (v.to.isEmpty ? "" : " → " + v.to), lines.joined(separator: "\n"))
    }

    /// The whole draft, every type: intro, free text, each week with every day's lines, scope and questions.
    @ViewBuilder private func plan(_ d: Draft, _ v: DraftVersion) -> some View {
        if v.intro.isEmpty && v.text.isEmpty && v.weeks.isEmpty && v.scope.isEmpty && v.questions.isEmpty {
            ContentUnavailableView("This draft has no text", systemImage: "doc.text", description: Text("Ask \(store.assistantName) to send it again.")).card()
        }
        if !v.intro.isEmpty { RichText(v.intro).card() }
        if !v.text.isEmpty { RichText(v.text).card() }
        ForEach(v.weeks) { w in DraftWeekCard(week: w, approved: store.review(d, v.version, w.id) != nil) }
        if !v.scope.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Full scope and source notes").font(.headline)
                Text(v.scope).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading).card()
        }
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
        let parts: [String?] = [v.by.isEmpty ? nil : "Written by \(v.by)", "version \(v.version)", v.createdAt.isEmpty ? nil : store.ago(isoMillis(v.createdAt))]
        let meta = parts.compactMap { $0 }
        Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary)
    }
    private func isoMillis(_ s: String) -> Double { (ISO8601DateFormatter().date(from: s) ?? ISO8601DateFormatter.fractional.date(from: s) ?? .now).timeIntervalSince1970 * 1000 }

    @ViewBuilder private func review(_ d: Draft, _ v: DraftVersion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your review").font(.headline)
            if d.parts.count > 1 {
                Picker("Week", selection: $week) { ForEach(d.parts) { w in Text(w.title + (store.review(d, v.version, w.id) != nil ? " ✓" : "")).tag(w.id) } }
                    .pickerStyle(.menu)
            }
            Toggle(d.isEmail ? "I checked the recipient and the text" : d.parts.count > 1 ? "I reviewed this week and accept the assumptions" : "I reviewed this draft and accept the assumptions", isOn: $reviewed).font(.subheadline)
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
                    Label(historyText(d, r), systemImage: r["state"].str.hasPrefix("sent to") ? "paperplane" : r["action"].str == "approve" ? "checkmark.seal" : "pencil").font(.footnote)
                }
            }
            .card()
        }
    }
    private func historyText(_ d: Draft, _ r: JSON) -> String {
        let state = r["state"].str, when = " · " + store.ago(r["at"].double ?? 0)
        if state.hasPrefix("sent to") { return "Sent to" + String(state.dropFirst("sent to".count)) + " · v" + r["version"].str + when }
        let part = d.parts.first { $0.id == r["week"].str }?.title ?? r["week"].str
        return (r["action"].str == "approve" ? "Approved " : "Changes requested: ") + part + when
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

/// One week of a plan draft, open by default so the whole text is readable.
struct DraftWeekCard: View {
    let week: DraftWeek
    let approved: Bool
    @State private var open = true
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(week.days) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.title).font(.subheadline.weight(.semibold))
                        if !day.subtitle.isEmpty { Text(day.subtitle).font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(day.lines.enumerated()), id: \.offset) { _, l in
                            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•").foregroundStyle(.secondary); Text(l) }.font(.footnote)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        } label: {
            HStack { Text(week.title).font(.body.weight(.semibold)); Spacer(); if approved { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) } }
        }
        .card()
    }
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
}
