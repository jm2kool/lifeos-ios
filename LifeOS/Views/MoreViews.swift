import SwiftUI

// MARK: Calendar (read-only snapshot)
struct CalendarView: View {
    @Environment(Store.self) private var store
    @State private var selected: String?
    @State private var q = ""
    @State private var showPast = false

    var body: some View {
        let today = store.today
        let days = (0..<7).map { store.addDays(today, $0) }
        let busy = Set(store.events.map { store.day($0) })
        var list = store.events.filter { showPast || store.end($0) > Date() || store.day($0) == today }
        if let selected { list = store.events.filter { store.day($0) == selected } }
        if !q.isEmpty { list = store.events.filter { ($0.title + " " + $0.note + " " + store.dayLabel(store.day($0))).localizedCaseInsensitiveContains(q) } }
        let groups = Dictionary(grouping: list, by: { store.day($0) }).sorted { $0.key < $1.key }
        return List {
            Section {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { d in
                        let on = d == selected
                        Button { withAnimation(.smooth) { selected = on ? nil : d } } label: {
                            VStack(spacing: 4) {
                                Text(store.date(d, minutes: 720).formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(on ? AnyShapeStyle(.background) : AnyShapeStyle(.secondary))
                                Text(store.date(d, minutes: 720).formatted(.dateTime.day())).font(.system(.title3, design: .rounded, weight: .semibold))
                                    .foregroundStyle(on ? AnyShapeStyle(.background) : d == today ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                                Circle().fill(busy.contains(d) ? (on ? AnyShapeStyle(.background) : AnyShapeStyle(.tint)) : AnyShapeStyle(Color.clear)).frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(on ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.clear), in: .rect(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if groups.isEmpty { ContentUnavailableView(q.isEmpty ? "Nothing scheduled" : "No matches", systemImage: "calendar") }
            ForEach(groups, id: \.key) { day, events in
                Section(store.relDay(day)) {
                    ForEach(events) { e in Button { store.sheet = .event(e.id) } label: { EventRow(event: e) }.buttonStyle(.plain).listRowInsets(EdgeInsets()) }
                }
            }
            Section {
                Toggle("Show past events", isOn: $showPast)
            } footer: {
                let c = store.checked(store.allEvents.map(\.checkedAt).max() ?? "")
                Text("\(c.label). LifeOS shows a snapshot of your calendar and never edits it.")
            }
        }
        .searchable(text: $q, prompt: "Search events")
        .navigationTitle("Calendar")
    }
}

// MARK: Timetable
struct TimetableView: View {
    @Environment(Store.self) private var store
    var body: some View {
        let _ = store.tick
        let blocks = store.timetableBlocks.filter { $0.end > Date() || $0.day == store.today }
        let days = Array(Set(blocks.map(\.day))).sorted()
        List {
            if days.isEmpty {
                ContentUnavailableView {
                    Label("No upcoming blocks", systemImage: "clock")
                } description: { Text("Add a block, paste a day as text, or ask Gemini to plan one.") } actions: {
                    Button("Add a block") { store.sheet = .addBlock }.buttonStyle(.glassProminent)
                }
            }
            ForEach(days, id: \.self) { d in
                Section(store.relDay(d) + (store.dayDiff(d, store.today) > 1 ? "" : " · " + store.dayLabel(d, long: false))) {
                    ForEach(blocks.filter { $0.day == d }) { b in
                        let now = Date()
                        BlockRow(block: b, state: b.end <= now ? .past : (b.start <= now ? .now : .later)).listRowInsets(EdgeInsets())
                    }
                }
            }
        }
        .navigationTitle("Timetable")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { store.sheet = .addBlock } }
            ToolbarItem(placement: .topBarTrailing) { Button("Edit as text", systemImage: "text.alignleft") { store.sheet = .editTimetable } }
        }
    }
}

// MARK: Feed
struct FeedView: View {
    @Environment(Store.self) private var store
    @State private var filter = "All"
    var body: some View {
        let items = store.feed
        let cats = ["All"] + items.map(\.category).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cats, id: \.self) { c in
                            Button(c) { withAnimation(.smooth) { filter = c } }
                                .buttonStyle(.glass).tint(filter == c ? .accentColor : nil).fontWeight(filter == c ? .semibold : .regular)
                        }
                    }
                    .padding(.horizontal, UI.gutter)
                }
                .padding(.horizontal, -UI.gutter)
                let shown = filter == "All" ? items : items.filter { $0.category == filter }
                let music = shown.filter(\.isMusic), other = shown.filter { !$0.isMusic }
                if filter == "All" && !music.isEmpty { SectionHeader(title: "Music radar"); group(music) }
                SectionHeader(title: filter == "All" ? (music.isEmpty ? "Latest" : "Everything else") : filter)
                group(filter == "All" ? other : shown)
            }
            .padding(.horizontal, UI.gutter).padding(.bottom, 30)
        }
        .pageBackground()
        .navigationTitle("Feed")
    }
    private func group(_ l: [FeedItem]) -> some View {
        VStack(spacing: 0) {
            if l.isEmpty { EmptyNote(text: "Nothing here yet.") }
            ForEach(l) { f in
                Button { store.sheet = .feed(f.id) } label: { FeedRow(item: f) }.buttonStyle(.plain)
                if f.id != l.last?.id { Divider().padding(.leading, 14) }
            }
        }.card(padding: 0)
    }
}

// MARK: Saved
struct SavedView: View {
    @Environment(Store.self) private var store
    var body: some View {
        List {
            if store.saved.isEmpty { ContentUnavailableView("Nothing saved", systemImage: "bookmark", description: Text("Save links from Feed, Inbox and Study, or add one here.")) }
            ForEach(store.saved) { s in
                Group {
                    if let u = s.link { Link(destination: u) { savedRow(s) } } else { savedRow(s) }
                }
                .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { store.act(["op": "saved.remove", "id": .string(s.id), "title": .string(s.title)], undo: "Removed") } }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { EditBuffer.shared.saved = s; store.sheet = .addSaved }
                    if let u = s.link { ShareLink(item: u) }
                    Button("Send to \(store.assistantName)", systemImage: "message") { store.sheet = .delegate("From LifeOS saved:\n\(s.title)\n\(s.url)\n\(s.note)\n\nWhat I want done: ") }
                }
            }
        }
        .navigationTitle("Saved")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { EditBuffer.shared.saved = nil; store.sheet = .addSaved } } }
    }
    private func savedRow(_ s: SavedItem) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: s.link == nil ? "bookmark.fill" : "link", color: .yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).foregroundStyle(.primary).lineLimit(2)
                Text(s.note.isEmpty ? (s.link?.host() ?? s.source) : s.note).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: Finances
struct FinancesView: View {
    @Environment(Store.self) private var store
    @State private var adding = false
    @State private var name = ""
    @State private var price = ""
    @State private var renews = ""
    var body: some View {
        let subs = store.content["subscriptions"].array
        let cur = store.content["currency"].string ?? "₹"
        let total = subs.reduce(0.0) { $0 + ($1["p"].double ?? 0) }
        List {
            if subs.isEmpty {
                ContentUnavailableView("No subscriptions", systemImage: "creditcard", description: Text(store.content["copy"]["financesEmpty"].string ?? "Track subscriptions and catch price changes."))
            } else {
                Section {
                    HStack {
                        VStack(alignment: .leading) { Text("Each month").font(.footnote).foregroundStyle(.secondary); Text(cur + String(format: "%.0f", total)).font(UI.number(28)) }
                        Spacer()
                        VStack(alignment: .trailing) { Text("Each year").font(.footnote).foregroundStyle(.secondary); Text(cur + String(format: "%.0f", total * 12)).font(UI.number(28)) }
                    }
                }
                Section("Subscriptions") {
                    ForEach(Array(subs.enumerated()), id: \.offset) { i, s in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s["n"].str)
                                if let w = s["w"].double, let p = s["p"].double, w != p {
                                    Text("\(p > w ? "Up" : "Down") from \(cur)\(String(format: "%.2f", w))").font(.footnote).foregroundStyle(p > w ? .red : .green)
                                } else if !s["d"].str.isEmpty { Text("Renews \(s["d"].str)").font(.footnote).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(cur + String(format: "%.2f", s["p"].double ?? 0)).fontWeight(.semibold)
                        }
                        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { var l = subs; l.remove(at: i); store.act(["op": "content.set", "path": "subscriptions", "value": .array(l)], undo: "Removed") } }
                    }
                }
            }
        }
        .navigationTitle("Finances")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { adding = true } } }
        .alert("Add subscription", isPresented: $adding) {
            TextField("Name", text: $name)
            TextField("Price per month", text: $price).keyboardType(.decimalPad)
            TextField("Renews (e.g. 3 Nov)", text: $renews)
            Button("Add") {
                if let p = Double(price), !name.isEmpty {
                    store.act(["op": "content.push", "path": "subscriptions", "value": ["id": .string(Reducer.uid("sub")), "n": .string(name), "p": .number(p), "w": .number(p), "d": .string(renews)], "title": .string(name)])
                }
                name = ""; price = ""; renews = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: Workflows
struct WorkflowsView: View {
    @Environment(Store.self) private var store
    @State private var adding = false
    @State private var step = ""
    var body: some View {
        let w = store.content["workflows"]
        List {
            if w["steps"].array.isEmpty {
                ContentUnavailableView("No workflows", systemImage: "bolt", description: Text(store.content["copy"]["workflowsEmpty"].string ?? "Write down steps you repeat."))
            } else {
                Toggle("Workflow on", isOn: Binding(get: { w["on"].bool }, set: { v in var x = w; x["on"] = .bool(v); store.act(["op": "content.set", "path": "workflows", "value": x]) }))
                Section("Steps") {
                    ForEach(Array(w["steps"].array.enumerated()), id: \.offset) { i, s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Step \(i + 1)").font(.caption).foregroundStyle(.secondary)
                            Text(s["k"].str)
                            if !s["x"].str.isEmpty { Text(s["x"].str).font(.footnote).foregroundStyle(.secondary) }
                        }
                        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { var x = w; var st = x["steps"].array; st.remove(at: i); x["steps"] = .array(st); store.act(["op": "content.set", "path": "workflows", "value": x]) } }
                    }
                }
            }
        }
        .navigationTitle("Workflows")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { adding = true } } }
        .alert("Add a step", isPresented: $adding) {
            TextField("Step", text: $step)
            Button("Add") {
                var x = w.isObject ? w : ["on": false, "steps": []]
                var st = x["steps"].array; st.append(["k": .string(step), "f": "", "x": ""]); x["steps"] = .array(st)
                store.act(["op": "content.set", "path": "workflows", "value": x]); step = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
