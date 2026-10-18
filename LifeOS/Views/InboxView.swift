import SwiftUI

struct InboxView: View {
    @Environment(Store.self) private var store
    @State private var showDone = false

    var body: some View {
        let list = store.mail.filter { store.inboxDone($0.id) == showDone }
            .sorted { rank(store.priority($0)) < rank(store.priority($1)) }
        let groups = Dictionary(grouping: list, by: \.account).sorted { $0.key < $1.key }
        List {
            Section {
                Picker("Show", selection: $showDone) {
                    Text("To review").tag(false)
                    Text("Done").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if list.isEmpty {
                ContentUnavailableView(showDone ? "Nothing done yet" : "Inbox zero", systemImage: showDone ? "checkmark.circle" : "tray",
                                       description: Text(showDone ? "Emails you mark done show up here." : "Your assistant adds important emails here."))
            }
            ForEach(groups, id: \.key) { account, rows in
                Section {
                    ForEach(rows) { m in
                        NavigationLink(value: m) { MailRow(mail: m) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(showDone ? "Reopen" : "Done", systemImage: showDone ? "arrow.uturn.backward" : "checkmark") {
                                    store.act(["op": "inbox.done", "id": .string(m.id), "done": .bool(!showDone), "title": .string(m.title)], undo: showDone ? nil : "Marked done")
                                }.tint(.green)
                            }
                            .swipeActions(edge: .leading) {
                                Button(store.snoozed(m.id) ? "Unsnooze" : "Snooze", systemImage: "moon.zzz") {
                                    store.act(["op": "inbox.snooze", "id": .string(m.id), "on": .bool(!store.snoozed(m.id))])
                                }.tint(.indigo)
                            }
                    }
                } header: {
                    Text(account)
                } footer: {
                    let c = store.checked(rows.map(\.checkedAt).max() ?? "")
                    Text(c.label + (c.stale ? ". May be out of date." : "")).foregroundStyle(c.stale ? .orange : .secondary)
                }
            }
            if let note = store.content["copy"]["inboxNote"].string, !note.isEmpty {
                Section { DisclosureGroup("About this inbox") { Text(note).font(.footnote).foregroundStyle(.secondary) } }
            }
        }
        .navigationTitle("Inbox")
        .pageBackground()
        .navigationSubtitle(store.inboxTodo.isEmpty ? "All reviewed" : "\(store.inboxTodo.count) to review")
        .navigationDestination(for: Mail.self) { MailDetail(mail: $0) }
        .navigationDestination(for: LibraryPage.self) { $0.view }
        .refreshable { await store.pull() }
    }
    private func rank(_ p: String) -> Int { ["High": 0, "Medium": 1, "Normal": 2, "Low": 3][p] ?? 2 }
}

struct MailRow: View {
    @Environment(Store.self) private var store
    let mail: Mail
    var body: some View {
        let p = store.priority(mail)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(p == "High" ? Color.red : p == "Medium" ? .orange : .secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(mail.senderName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if store.replyDraft(for: mail) != nil { Pill(text: "Reply ready", color: .blue, icon: "sparkles") }
                if store.snoozed(mail.id) { Image(systemName: "moon.zzz.fill").font(.caption).foregroundStyle(.indigo) }
            }
            Text(mail.title).font(.body).lineLimit(2)
            if !mail.gist.isEmpty { Text(mail.gist).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
        }
        .padding(.vertical, 2)
    }
}

struct MailDetail: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let mail: Mail
    @State private var drafting = false

    var body: some View {
        let done = store.inboxDone(mail.id)
        let draft = store.replyDraft(for: mail)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mail.title).font(.title2.weight(.bold))
                    Text("\(mail.sender) · \(mail.account)").font(.subheadline).foregroundStyle(.secondary)
                }
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(done ? "Reopen" : "Done", systemImage: done ? "arrow.uturn.backward" : "checkmark") {
                            store.act(["op": "inbox.done", "id": .string(mail.id), "done": .bool(!done)], undo: done ? nil : "Marked done")
                            if !done { dismiss() }
                        }.buttonStyle(.glassProminent)
                        Menu {
                            ForEach(["High", "Medium", "Low", "Normal"], id: \.self) { p in
                                Button(p) { store.act(["op": "inbox.priority", "id": .string(mail.id), "value": .string(p == "Normal" ? "" : p)]) }
                            }
                        } label: { Label(store.priority(mail), systemImage: "flag") }.buttonStyle(.glass)
                        Button(store.snoozed(mail.id) ? "Snoozed" : "Snooze", systemImage: "moon.zzz") {
                            store.act(["op": "inbox.snooze", "id": .string(mail.id), "on": .bool(!store.snoozed(mail.id))])
                        }.buttonStyle(.glass)
                    }
                    .controlSize(.small)
                }
                Text(mail.body.isEmpty ? mail.gist : mail.body).font(.body).textSelection(.enabled).card()
                let c = store.checked(mail.checkedAt)
                Text(c.label + ". Marking done changes LifeOS, not your mailbox.").font(.caption).foregroundStyle(c.stale ? .orange : .secondary)

                if let draft {
                    NavigationLink(value: LibraryPage.draft(draft.id)) {
                        HStack {
                            IconTile(symbol: "envelope.fill", color: .blue)
                            VStack(alignment: .leading) { Text("Reply draft ready").font(.body.weight(.semibold)); Text(draft.latest?.subject ?? "").font(.footnote).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.card(padding: 14)
                    }.buttonStyle(.plain)
                }
                VStack(spacing: 10) {
                    Button {
                        drafting = true
                        Task { do { try await assistant.draftReply(for: mail) } catch { store.show(error.localizedDescription) }; drafting = false }
                    } label: {
                        HStack { if drafting { ProgressView() } else { Image(systemName: "sparkles") }; Text(draft == nil ? "Draft a reply with Gemini" : "Write a new draft") }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large).disabled(drafting || !assistant.available)
                    HStack(spacing: 10) {
                        Button { store.act(["op": "saved.add", "title": .string(mail.title), "url": .string(mail.url), "source": "Inbox"]); store.show("Saved") } label: { Label("Save", systemImage: "bookmark").frame(maxWidth: .infinity) }
                        Button { store.sheet = .delegate("From LifeOS inbox (\(mail.account)):\n\(mail.title)\nFrom \(mail.sender)\n\(mail.gist)\n\nWhat I want done: ") } label: { Label("Send to \(store.assistantName)", systemImage: "message").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.glass).controlSize(.large)
                    if let u = URL(string: mail.url), mail.url.hasPrefix("http") { Link(destination: u) { Label("Open original", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }.buttonStyle(.glass).controlSize(.large) }
                }
            }
            .padding(UI.gutter)
        }
        .pageBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
