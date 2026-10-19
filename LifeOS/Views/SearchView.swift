import SwiftUI
import UIKit

struct SearchView: View {
    @Environment(Store.self) private var store
    @State private var q = ""

    struct Hit: Identifiable { let id = UUID(); let group: String; let title: String; let sub: String; let symbol: String; let color: Color; let go: () -> Void }

    var body: some View {
        let hits = results()
        List {
            Section {
                Button { store.sheet = .ask(q) } label: {
                    Label { VStack(alignment: .leading) { Text("Ask Gemini"); Text(q.isEmpty ? "About your day, or to change something" : "“\(q)”").font(.footnote).foregroundStyle(.secondary) } } icon: { IconTile(symbol: "sparkles", color: .purple) }
                }
                if q.isEmpty {
                    Button { store.sheet = .capture } label: { Label { Text("Capture something") } icon: { IconTile(symbol: "plus", color: .green) } }
                    Button { store.sheet = .focus } label: { Label { Text("Start focus") } icon: { IconTile(symbol: "timer", color: .orange) } }
                }
            }
            .buttonStyle(.plain)
            ForEach(Array(Set(hits.map(\.group))).sorted(), id: \.self) { g in
                Section(g) {
                    ForEach(hits.filter { $0.group == g }) { h in
                        Button(action: h.go) {
                            Label { VStack(alignment: .leading, spacing: 2) { Text(h.title).lineLimit(2); if !h.sub.isEmpty { Text(h.sub).font(.footnote).foregroundStyle(.secondary).lineLimit(1) } } } icon: { IconTile(symbol: h.symbol, color: h.color) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !q.isEmpty && hits.isEmpty { ContentUnavailableView.search(text: q) }
        }
        .navigationTitle("Search")
        .pageBackground()
        .searchable(text: $q, prompt: "Tasks, events, emails, notes")
    }

    private func results() -> [Hit] {
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return [] }
        func m(_ s: String...) -> Bool { s.joined(separator: " ").lowercased().contains(t) }
        var out: [Hit] = []
        for x in store.tasks where m(x.title, x.note) { out.append(Hit(group: "Tasks", title: x.title, sub: store.isDone(x.id) ? "Done" : store.dueText(x.due), symbol: "checkmark", color: .blue) { store.go(.today) }) }
        for x in store.cards where m(x.title, x.note) { out.append(Hit(group: "Board", title: x.title, sub: Reducer.columns[min(2, x.column)], symbol: "rectangle.split.3x1", color: .green) { store.go(.board) }) }
        for x in store.mail where m(x.title, x.gist, x.sender) { out.append(Hit(group: "Inbox", title: x.title, sub: x.senderName, symbol: "tray", color: .blue) { store.sheet = .inbox(x.id) }) }
        for x in store.events where m(x.title, x.note) { out.append(Hit(group: "Calendar", title: x.title, sub: store.relDay(store.day(x)), symbol: "calendar", color: .red) { store.sheet = .event(x.id) }) }
        for x in store.feed where m(x.title, x.desc) { out.append(Hit(group: "Feed", title: x.title, sub: x.category, symbol: "dot.radiowaves.up.forward", color: .orange) { store.sheet = .feed(x.id) }) }
        for x in store.saved where m(x.title, x.note) { out.append(Hit(group: "Saved", title: x.title, sub: x.source, symbol: "bookmark", color: .yellow) { if let u = x.link { UIApplication.shared.open(u) } }) }
        for x in store.drafts where m(x.title) { out.append(Hit(group: "Drafts", title: x.title, sub: x.isEmail ? "Email" : "Plan", symbol: "doc.text", color: .pink) { store.go(.drafts) }) }
        for s in store.coverage where m(s.name) { out.append(Hit(group: "Coverage", title: s.name, sub: "\(s.group) · \(store.doneCount(s))/\(s.items.count)", symbol: "target", color: .green) { store.go(.study) }) }
        return out
    }
}
