import SwiftUI

/// The tab bar is yours to arrange: pick up to four screens and their order in Settings › Tab bar.
/// Everything else lives under More, which (with Search) is always there.
extension AppTab {
    static let customisable: [AppTab] = [.today, .inbox, .study, .board, .drafts, .calendar, .timetable, .feed, .saved, .finances, .workflows]
    static let defaultBar: [AppTab] = [.today, .inbox, .study]
    static let maxInBar = 4

    var title: String {
        switch self {
        case .today: "Today"; case .inbox: "Inbox"; case .study: "Study"; case .board: "Board"; case .drafts: "Drafts"
        case .calendar: "Calendar"; case .timetable: "Timetable"; case .feed: "Feed"; case .saved: "Saved"
        case .finances: "Finances"; case .workflows: "Workflows"; case .library: "More"; case .search: "Search"
        }
    }
    /// Tab bar symbol (outline style, like the system tabs).
    var symbol: String {
        switch self {
        case .today: "sun.max"; case .inbox: "tray"; case .study: "book.closed"; case .board: "rectangle.split.3x1"
        case .drafts: "doc.text"; case .calendar: "calendar"; case .timetable: "clock"; case .feed: "dot.radiowaves.up.forward"
        case .saved: "bookmark"; case .finances: "creditcard"; case .workflows: "bolt"; case .library: "ellipsis.circle"
        case .search: "magnifyingglass"
        }
    }
    /// Filled symbol and colour for the rows in More.
    var tile: (String, Color) {
        switch self {
        case .today: ("sun.max.fill", .orange); case .inbox: ("tray.fill", .blue); case .study: ("book.closed.fill", .green)
        case .board: ("rectangle.split.3x1.fill", .green); case .drafts: ("doc.text.fill", .pink); case .calendar: ("calendar", .red)
        case .timetable: ("clock.fill", .blue); case .feed: ("dot.radiowaves.up.forward", .orange); case .saved: ("bookmark.fill", .yellow)
        case .finances: ("creditcard.fill", .teal); case .workflows: ("bolt.fill", .indigo); case .library: ("ellipsis.circle.fill", .gray)
        case .search: ("magnifyingglass", .gray)
        }
    }
    /// The page that shows this screen when it's opened inside More (or as its own tab).
    var page: LibraryPage? {
        switch self {
        case .today: .today; case .inbox: .inbox; case .study: .study; case .board: .board; case .drafts: .drafts
        case .calendar: .calendar; case .timetable: .timetable; case .feed: .feed; case .saved: .saved
        case .finances: .finances; case .workflows: .workflows; case .library, .search: nil
        }
    }
    var palette: AmbientPalette {
        switch self { case .today: .today; case .inbox: .inbox; case .study: .study; case .search: .search; default: .library }
    }
}

extension Store {
    /// The screens in the tab bar, in your order (settings.ui.tabs). Starts as Today, Inbox, Study.
    var barTabs: [AppTab] {
        let raw = doc["settings"]["ui"]["tabs"]
        guard raw.isArray else { return AppTab.defaultBar }
        var out: [AppTab] = []
        for v in raw.array { if let t = AppTab(rawValue: v.str), AppTab.customisable.contains(t), !out.contains(t) { out.append(t) } }
        return Array(out.prefix(AppTab.maxInBar))
    }
    /// The screens under More, in the usual order.
    var moreTabs: [AppTab] { AppTab.customisable.filter { !barTabs.contains($0) } }

    func setBarTabs(_ tabs: [AppTab]) {
        act(["op": "settings.set", "value": ["ui": ["tabs": .array(tabs.prefix(AppTab.maxInBar).map { .string($0.rawValue) })]]], quiet: true)
        if tab != .library && tab != .search && !barTabs.contains(tab) { tab = .library; libraryPath = [] }
    }

    /// Opens a screen wherever it lives (its own tab, or inside More), then pushes `then` on top of it.
    func go(_ t: AppTab, then path: [LibraryPage] = []) {
        if t == .library || t == .search || barTabs.contains(t) {
            tab = t
            if t == .library { libraryPath = path } else if t != .search { tabPaths[t] = path }
        } else if let p = t.page {
            tab = .library; libraryPath = [p] + path
        }
    }
    func pathBinding(_ t: AppTab) -> Binding<[LibraryPage]> {
        Binding(get: { self.tabPaths[t] ?? [] }, set: { self.tabPaths[t] = $0 })
    }
}

/// Settings › Tab bar.
struct TabBarSettings: View {
    @Environment(Store.self) private var store
    @State private var bar: [AppTab] = []

    var body: some View {
        List {
            Section {
                ForEach(bar, id: \.self) { t in
                    Label(t.title, systemImage: t.symbol)
                        .swipeActions { Button("Move to More") { bar.removeAll { $0 == t }; save() }.tint(.gray) }
                }
                .onMove { from, to in bar.move(fromOffsets: from, toOffset: to); save() }
                .onDelete { bar.remove(atOffsets: $0); save() }
                LabeledContent { Text("Always") } label: { Label("More", systemImage: AppTab.library.symbol) }.foregroundStyle(.secondary)
                LabeledContent { Text("Always") } label: { Label("Search", systemImage: AppTab.search.symbol) }.foregroundStyle(.secondary)
            } header: { Text("In the tab bar") } footer: {
                Text("Drag to reorder. Up to \(AppTab.maxInBar), plus More and Search.")
            }
            Section("Under More") {
                ForEach(AppTab.customisable.filter { !bar.contains($0) }, id: \.self) { t in
                    Button { bar.append(t); save() } label: {
                        HStack { Label(t.title, systemImage: t.symbol).foregroundStyle(.primary); Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(bar.count >= AppTab.maxInBar ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.green)) }
                    }
                    .disabled(bar.count >= AppTab.maxInBar)
                }
            }
            Section { Button("Back to the usual tabs") { bar = AppTab.defaultBar; save() } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab bar")
        .onAppear { bar = store.barTabs }
    }
    private func save() { store.setBarTabs(bar) }
}
