import SwiftUI
import UIKit

struct SheetHost: View {
    @Environment(Store.self) private var store
    let route: SheetRoute
    var body: some View {
        switch route {
        case .ask(let q): AskView(prefill: q).presentationDetents([.large])
        case .capture: CaptureSheet().presentationDetents([.medium, .large])
        case .focus: FocusSheet().presentationDetents([.large])
        case .inbox(let id): NavigationStack { if let m = store.mail.first(where: { $0.id == id }) { MailDetail(mail: m) } }
        case .feed(let id): FeedSheet(id: id).presentationDetents([.medium, .large])
        case .event(let id): EventSheet(id: id).presentationDetents([.medium])
        case .addTask: TaskSheet().presentationDetents([.medium, .large])
        case .addSaved: SavedSheet().presentationDetents([.medium, .large])
        case .addBlock: BlockSheet().presentationDetents([.medium, .large])
        case .editTimetable: TimetableTextSheet()
        case .settings: SettingsView()
        case .onboarding: OnboardingView().interactiveDismissDisabled()
        case .delegate(let text): DelegateSheet(text: text).presentationDetents([.medium, .large])
        case .activity: ActivitySheet()
        }
    }
}

// MARK: Ask Gemini
struct AskView: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State var prefill: String
    @FocusState private var focused: Bool
    private let suggestions = ["What should I focus on now?", "Plan my evening around tuition", "Draft replies to emails that need one", "Move finished things to Done"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if assistant.chat.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.tint).padding(.top, 30)
                                Text("Ask Gemini").font(.title2.weight(.bold))
                                Text("It sees your whole dashboard and can add, move and remove things, plan your day and draft emails. Every change can be undone.")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                if !assistant.available { Button("Add your Gemini key") { store.sheet = .settings }.buttonStyle(.glassProminent).padding(.top, 6) }
                            }
                            .frame(maxWidth: .infinity).padding(.horizontal)
                            FlowChips(items: suggestions) { s in Task { await assistant.send(s) } }.padding(.top, 8)
                        }
                        ForEach(assistant.chat) { m in Bubble(message: m).id(m.id) }
                        if assistant.busy { TypingDots().id("typing") }
                    }
                    .padding(UI.gutter)
                }
                .onChange(of: assistant.chat.count) { _, _ in if let id = assistant.chat.last?.id { withAnimation(.smooth) { proxy.scrollTo(id, anchor: .bottom) } } }
                .onChange(of: assistant.busy) { _, b in if b { withAnimation(.smooth) { proxy.scrollTo("typing", anchor: .bottom) } } }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask or tell Gemini to change something", text: $prefill, axis: .vertical)
                        .lineLimit(1...5).focused($focused).submitLabel(.send)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        .onSubmit(send)
                    Button(action: send) { Image(systemName: "arrow.up").font(.headline).frame(width: 30, height: 30) }
                        .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                        .disabled(prefill.trimmingCharacters(in: .whitespaces).isEmpty || assistant.busy)
                }
                .padding(.horizontal, UI.gutter).padding(.bottom, 8)
            }
            .navigationTitle("Gemini").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("New chat", systemImage: "square.and.pencil") { assistant.chat = [] } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "xmark") { dismiss() } }
            }
            .onAppear { if !prefill.isEmpty || assistant.chat.isEmpty { focused = true } }
        }
    }
    private func send() {
        let q = prefill.trimmingCharacters(in: .whitespacesAndNewlines); guard !q.isEmpty, !assistant.busy else { return }
        prefill = ""
        Task { await assistant.send(q) }
    }
}

struct Bubble: View {
    @Environment(Assistant.self) private var assistant
    let message: ChatMessage
    var body: some View {
        let me = message.role == "user"
        VStack(alignment: me ? .trailing : .leading, spacing: 6) {
            Text(LocalizedStringKey(message.text))
                .font(.body)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(me ? AnyShapeStyle(.background) : message.failed ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                .background(me ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: .rect(cornerRadius: 20, style: .continuous))
                .textSelection(.enabled)
            if !message.changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.changes, id: \.self) { c in Label(c, systemImage: "wand.and.stars").font(.footnote) }
                    HStack {
                        if !message.proposal.isEmpty {
                            Button("Apply") { assistant.approve(message) }.buttonStyle(.glassProminent)
                        } else if message.undoID != nil {
                            Button("Undo") { assistant.undo(message) }.buttonStyle(.glass)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: me ? .trailing : .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in Circle().frame(width: 7, height: 7).opacity(on ? 1 : 0.3).animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: on) }
        }
        .foregroundStyle(.secondary).padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
        .onAppear { on = true }
    }
}

struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { s in Button(s) { tap(s) }.buttonStyle(.glass) }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Capture
struct CaptureSheet: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var parsed: JSON = .null
    @State private var sorting = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("“Email Vedica back tomorrow”, a link, or “Physics revision Thursday 5pm”", text: $text, axis: .vertical)
                        .lineLimit(3...6).focused($focused)
                        .onChange(of: text) { _, t in parsed = t.isEmpty ? .null : localParse(t) }
                } footer: { Text("Tap the mic on your keyboard to dictate.") }
                if !parsed.isNull {
                    Section("Goes to") { Label(describe(parsed), systemImage: "wand.and.stars") }
                }
                Section {
                    Button("Add") { commit(parsed.isNull ? localParse(text) : parsed) }.disabled(text.isEmpty)
                    if assistant.available {
                        Button {
                            sorting = true
                            Task { do { let p = try await assistant.sortCapture(text); if p["type"].string != nil { parsed = p } } catch { store.show(error.localizedDescription) }; sorting = false }
                        } label: { HStack { Text("Sort it with Gemini"); Spacer(); if sorting { ProgressView() } } }.disabled(text.isEmpty || sorting)
                    }
                }
                Section("Or put it in") {
                    Button("To do") { commit(["type": "task", "title": .string(text)]) }
                    Button("Board") { commit(["type": "board", "title": .string(text)]) }
                    Button("Saved") { commit(["type": "saved", "title": .string(text), "url": JSON(firstURL(text))]) }
                }
                .disabled(text.isEmpty)
            }
            .navigationTitle("Capture").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
    private func firstURL(_ t: String) -> String? { t.split(separator: " ").first { $0.hasPrefix("http") }.map(String.init) }
    private func localParse(_ t: String) -> JSON {
        if let u = firstURL(t) { let title = t.replacingOccurrences(of: u, with: "").trimmingCharacters(in: .whitespaces); return ["type": "saved", "title": .string(title.isEmpty ? u : title), "url": .string(u)] }
        let low = t.lowercased(); var due: String?
        if low.contains("today") { due = store.today } else if low.contains("tomorrow") { due = store.addDays(store.today, 1) }
        else {
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            if let i = names.firstIndex(where: { low.contains($0) }) {
                let cur = store.cal.component(.weekday, from: Date()) - 1
                let ahead = (i - cur + 7) % 7
                due = store.addDays(store.today, ahead == 0 ? 7 : ahead)
            }
        }
        let clean = t.replacingOccurrences(of: #"\b(today|tomorrow|by|on)\b"#, with: "", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        if let due, let r = t.range(of: #"\b(\d{1,2})(:\d{2})?\s*(am|pm)\b"#, options: [.regularExpression, .caseInsensitive]), let m = Store.ttMinutes(String(t[r]).replacingOccurrences(of: " ", with: "")) {
            let title = clean.replacingOccurrences(of: String(t[r]), with: "").replacingOccurrences(of: " at ", with: " ").trimmingCharacters(in: .whitespaces)
            return ["type": "block", "title": .string(title), "date": .string(due), "start": .string(String(format: "%d:%02d", m / 60, m % 60)), "end": .string(String(format: "%d:%02d", (m + 60) / 60 % 24, m % 60))]
        }
        if let due { return ["type": "task", "title": .string(clean), "due": .string(due)] }
        return ["type": "board", "title": .string(t)]
    }
    private func describe(_ p: JSON) -> String {
        switch p["type"].str {
        case "saved": return "Saved: " + p["title"].str
        case "task": return "To do: " + p["title"].str + (p["due"].string.map { " · due " + store.relDay($0).lowercased() } ?? "")
        case "block": return "Timetable: " + p["title"].str + " · " + store.relDay(p["date"].str) + " " + p["start"].str
        default: return "Board: " + p["title"].str
        }
    }
    private func commit(_ p: JSON) {
        switch p["type"].str {
        case "saved": store.act(["op": "saved.add", "title": p["title"], "url": p["url"], "source": "Capture"], undo: "Saved")
        case "task": store.act(["op": "task.add", "title": p["title"], "due": p["due"]], undo: "Added to To do")
        case "block": store.act(assistant.expand([["op": "timetable.add_block", "date": p["date"], "start": p["start"], "end": p["end"], "title": p["title"]]]), undo: "Added to timetable")
        default: store.act(["op": "board.add", "title": p["title"], "filed": false], undo: "Added to Board")
        }
        dismiss()
    }
}

// MARK: Focus
struct FocusSheet: View {
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var minutes = 25
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if focus.running { running } else { setup }
                }
                .padding(.horizontal, UI.gutter).padding(.top, 6).padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Focus").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .onAppear {
                if label.isEmpty { label = store.now.current?.title ?? "" }
                minutes = UserDefaults.standard.integer(forKey: "focus.lastLength").clamped(5, 120, default: 25)
            }
        }
    }

    // MARK: before starting: the clock
    @ViewBuilder private var setup: some View {
        FocusDial(minutes: $minutes) {
            VStack(spacing: 0) {
                Text("\(minutes)").font(.system(size: 68, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(minutes)))
                Text("min").font(.headline).foregroundStyle(.secondary)
                Text("ends " + Date().addingTimeInterval(Double(minutes) * 60).formatted(date: .omitted, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            }
            .animation(.snappy, value: minutes)
        }
        .padding(.horizontal, 24)

        if let until = untilNext {
            Button { withAnimation(.smooth) { minutes = until.minutes } } label: {
                Label("Until \(until.title) · \(until.minutes) min", systemImage: "arrow.right.to.line").font(.footnote.weight(.medium)).lineLimit(1)
            }
            .buttonStyle(.glass)
        }

        VStack(alignment: .leading, spacing: 10) {
            TextField("What are you focusing on?", text: $label)
                .focused($typing).submitLabel(.done)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { label = s; typing = false }
                                .font(.footnote).lineLimit(1)
                                .buttonStyle(.glass)
                                .tint(s == label ? .accentColor : nil)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        Button {
            UserDefaults.standard.set(minutes, forKey: "focus.lastLength")
            focus.start(minutes: minutes, label: label.trimmingCharacters(in: .whitespaces)); dismiss()
        } label: { Label("Start \(minutes) min", systemImage: "play.fill").frame(maxWidth: .infinity) }
        .buttonStyle(.glassProminent).controlSize(.large)

        Text("It shows on your Lock Screen and in the Dynamic Island. Sessions of 20 minutes or more count toward your streak.")
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }

    // MARK: while it runs
    @ViewBuilder private var running: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            FocusDial(minutes: .constant(focus.minutes), progress: focus.progress) {
                VStack(spacing: 2) {
                    Text(focus.label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 50)
                    Text(Duration.seconds(focus.remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(focus.paused ? "Paused" : "ends " + focus.endDate.formatted(date: .omitted, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
        }
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(focus.paused ? "Resume" : "Pause", systemImage: focus.paused ? "play.fill" : "pause.fill") { focus.togglePause() }
                    .buttonStyle(.glassProminent)
                Button("End", systemImage: "stop.fill") { focus.stop(); dismiss() }.buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }

    /// Your current block, the next study block and a few open tasks, to tap instead of typing.
    private var suggestions: [String] {
        let (cur, next) = store.now
        var candidates: [String] = []
        if let c = cur { candidates.append(c.title) }
        if let n = next, n.kind == .study { candidates.append(n.title) }
        if focus.label != "Focus" { candidates.append(focus.label) }
        candidates += store.openTasks.prefix(3).map(\.title)
        var out: [String] = []
        for t in candidates where !t.isEmpty && !out.contains(t) { out.append(t) }
        return Array(out.prefix(5))
    }
    /// "Until Physics tuition · 45 min" when your next block starts within two hours.
    private var untilNext: (title: String, minutes: Int)? {
        guard let next = store.now.next else { return nil }
        let m = Int(next.start.timeIntervalSinceNow / 60) / 5 * 5
        return (5...120).contains(m) ? (next.title, m) : nil
    }
}

private extension Int {
    func clamped(_ lo: Int, _ hi: Int, default d: Int) -> Int { self == 0 ? d : Swift.min(hi, Swift.max(lo, self)) }
}

// MARK: small sheets
struct FeedSheet: View {
    @Environment(Store.self) private var store
    let id: String
    var body: some View {
        if let f = store.feed.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(f.category, systemImage: symbol(f.icon)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.token(f.colorToken))
                    Text(f.title).font(.title2.weight(.bold))
                    Text(f.desc).font(.body).foregroundStyle(.secondary)
                    HStack { ForEach(f.chips, id: \.self) { Pill(text: $0) } }
                    VStack(spacing: 10) {
                        if let u = URL(string: f.url), f.url.hasPrefix("http") { Link(destination: u) { Label("Read source", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent) }
                        Button { store.act(["op": "saved.add", "title": .string(f.title), "url": .string(f.url), "source": "Feed"]); store.show("Saved") } label: { Label("Save", systemImage: "bookmark").frame(maxWidth: .infinity) }.buttonStyle(.glass)
                        Button { store.sheet = .ask("Tell me more about: \(f.title). \(f.desc)") } label: { Label("Ask Gemini", systemImage: "sparkles").frame(maxWidth: .infinity) }.buttonStyle(.glass)
                    }
                    .controlSize(.large).padding(.top, 8)
                }
                .padding(24)
            }
        }
    }
}

struct EventSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String
    var body: some View {
        if let e = store.allEvents.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(e.title).font(.title2.weight(.bold))
                Text(store.dayLabel(store.day(e)) + (e.timed ? ", " + store.time(store.start(e)) + (e.end != nil ? " – " + store.time(store.end(e)) : "") : ", all day")).foregroundStyle(.tint).font(.headline)
                if !e.note.isEmpty { Text(e.note).foregroundStyle(.secondary) }
                Text("\(e.source) · \(store.checked(e.checkedAt).label)").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 10) {
                    if let u = URL(string: e.url), e.url.hasPrefix("http") { Link(destination: u) { Label("Open in \(e.source)", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }.buttonStyle(.glass) }
                    Button { store.act(["op": "task.add", "title": .string("Prep: " + e.title), "due": .string(store.day(e)), "src": "Calendar"], undo: "Task added"); dismiss() } label: { Label("Prep task", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.glass)
                }.controlSize(.large)
            }
            .padding(24)
        }
    }
}

struct TaskSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var editing: TaskItem?
    var body: some View {
        NavigationStack {
            Form {
                TextField("What needs doing?", text: $title)
                TextField("Note", text: $note, axis: .vertical).lineLimit(2...5)
                Toggle("Due date", isOn: $hasDue.animation())
                if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
            }
            .navigationTitle(editing == nil ? "New task" : "Edit task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") {
                        let d: JSON = hasDue ? .string(store.dayKey(due)) : ""
                        if let t = editing { store.act(["op": "task.update", "id": .string(t.id), "title": .string(title), "note": .string(note), "due": d]) }
                        else { store.act(["op": "task.add", "title": .string(title), "note": .string(note), "due": d], undo: "Task added") }
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let t = EditBuffer.shared.task { editing = t; title = t.title; note = t.note; if let d = t.due { hasDue = true; due = store.date(d, minutes: 720) } }
                EditBuffer.shared.task = nil
            }
        }
    }
}

struct SavedSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    @State private var note = ""
    @State private var editing: SavedItem?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("https://", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Note", text: $note, axis: .vertical)
            }
            .navigationTitle(editing == nil ? "Save a link" : "Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let s = editing { store.act(["op": "saved.update", "id": .string(s.id), "title": .string(title), "url": .string(url), "note": .string(note)]) }
                        else { store.act(["op": "saved.add", "title": .string(title), "url": .string(url), "note": .string(note)], undo: "Saved") }
                        dismiss()
                    }.disabled(title.isEmpty)
                }
            }
            .onAppear { if let s = EditBuffer.shared.saved { editing = s; title = s.title; url = s.url; note = s.note }; EditBuffer.shared.saved = nil }
        }
    }
}

struct BlockSheet: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var day = Date()
    @State private var start = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("What", text: $title)
                DatePicker("Day", selection: $day, displayedComponents: .date)
                DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Add a block").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let f: (Date) -> String = { d in let c = Calendar.current.dateComponents([.hour, .minute], from: d); return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0) }
                        let local = Calendar.current.dateComponents([.year, .month, .day], from: day)
                        let key = String(format: "%04d-%02d-%02d", local.year ?? 0, local.month ?? 0, local.day ?? 0)
                        store.act(assistant.expand([["op": "timetable.add_block", "date": .string(key), "start": .string(f(start)), "end": .string(f(end)), "title": .string(title)]]), undo: "Added to timetable")
                        dismiss()
                    }.disabled(title.isEmpty)
                }
            }
        }
    }
}

struct TimetableTextSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("One date per header (YYYY-MM-DD), then one block per line, like 7:00-13:00 Revise chapters. Saving a date replaces that whole day.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.system(.callout, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(8).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                Button("Reset to the shipped timetable", role: .destructive) { store.act(["op": "timetable.set", "text": ""], undo: "Timetable reset"); dismiss() }.font(.footnote)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit timetable").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let r = Store.ttParse(text)
                        if !r.bad.isEmpty { error = "Couldn't read line " + r.bad.prefix(5).map { String($0) }.joined(separator: ", ") + ". Nothing saved."; return }
                        store.act(["op": "timetable.set", "text": .string(text)], undo: "Timetable saved"); dismiss()
                    }
                }
            }
            .onAppear { text = Store.ttText(store.timetableDays) }
        }
    }
}

struct DelegateSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Message", text: $text, axis: .vertical).lineLimit(5...12)
                } footer: {
                    Text(store.assistantAddress.isEmpty ? "Add your assistant's iMessage address in Settings to open Messages directly." : "Opens Messages to \(store.assistantAddress). Nothing sends until you tap send there.")
                }
                Section {
                    if !store.assistantAddress.isEmpty {
                        Button("Open in Messages", systemImage: "message.fill") {
                            var c = URLComponents(); c.scheme = "sms"; c.path = store.assistantAddress
                            c.queryItems = [URLQueryItem(name: "body", value: text)]
                            if let u = c.url { openURL(u) }; dismiss()
                        }
                    }
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text; store.show("Copied") }
                    ShareLink(item: text) { Label("Share…", systemImage: "square.and.arrow.up") }
                }
            }
            .navigationTitle("Send to \(store.assistantName)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct ActivitySheet: View {
    @Environment(Store.self) private var store
    var body: some View {
        NavigationStack {
            List {
                if !store.undoStack.isEmpty {
                    Section("Undo") {
                        ForEach(store.undoStack.reversed()) { e in
                            HStack { Text(e.label); Spacer(); Text(e.at, style: .relative).font(.caption).foregroundStyle(.secondary) }
                        }
                        Button("Undo the last change", systemImage: "arrow.uturn.backward") { store.undoLast() }
                    }
                }
                Section {
                    ForEach(Array(store.state["log"].array.enumerated()), id: \.offset) { _, l in ActivityRow(entry: l) }
                } header: { Text("Recent changes") } footer: {
                    Text(store.syncURL.isEmpty ? "Turn on sync to see and undo changes your assistants make." : "Anything changed through your server can be undone here, whoever made it. Undoing is logged too, so it can be undone again.")
                }
            }
            .navigationTitle("Activity")
            .onAppear { store.markChangesSeen() }
        }
    }
}

/// One change in Activity: what happened, who did it, and Undo.
struct ActivityRow: View {
    @Environment(Store.self) private var store
    let entry: JSON
    @State private var busy = false
    var body: some View {
        let undone = !entry["undone"].isNull
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.describe(entry)).font(.subheadline).lineLimit(3).strikethrough(undone, color: .secondary)
                HStack(spacing: 6) {
                    ChangedByTag(by: entry["by"].str)
                    Text(store.ago(entry["at"].double ?? 0)).font(.caption).foregroundStyle(.secondary)
                }
                if undone { Text("Undone by \(entry["undone"]["by"].str) · \(store.ago(entry["undone"]["at"].double ?? 0))").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if !undone && !entry["undo"].isNull && !entry["id"].isNull && !store.syncURL.isEmpty {
                Button { busy = true; Task { await store.undoOnServer([entry["id"].str]); busy = false } } label: {
                    if busy { ProgressView() } else { Text("Undo") }
                }
                .buttonStyle(.glass).controlSize(.small).disabled(busy)
            }
        }
    }
}
