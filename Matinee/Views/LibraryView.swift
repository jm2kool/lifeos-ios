import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Pane: String, CaseIterable { case watchlist = "Watchlist", films = "Films", likes = "Likes", lists = "Lists" }
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @AppStorage("librarySection") private var section: Pane = .watchlist
    @AppStorage("watchlistSort") private var sortByTitle = false
    @State private var importer = Importer()
    @State private var importingWatchlist = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Section", selection: $section) {
                    ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                switch section {
                case .watchlist: watchlist
                case .films: films
                case .likes: likes
                case .lists: lists
                }
            }
            .padding(.vertical, 8)
            .animation(.smooth, value: section)
        }
        .ambientBackground(glowFilms)
        .sheet(isPresented: $importingWatchlist) {
            CSVPicker { urls in
                section = .watchlist
                Task { await importer.run(urls, into: library, forceKind: .watchlist) }
            }
            .ignoresSafeArea()
        }
        .navigationTitle("Library")
        .toolbar {
            if section == .lists {
                ToolbarItem(placement: .topBarTrailing) { Button("New list", systemImage: "plus") { router.sheet = .newList(nil) } }
            }
            if section == .watchlist {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import Letterboxd watchlist…", systemImage: "square.and.arrow.down") { importingWatchlist = true }
                        if !library.doc.watchlist.isEmpty {
                            Picker("Sort", selection: $sortByTitle) {
                                Text("Recently added").tag(false)
                                Text("Title").tag(true)
                            }
                            Button("Random pick", systemImage: "dice") { router.pickRandom(from: library) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                }
            }
        }
    }

    private var glowFilms: [FilmRef] {
        switch section {
        case .watchlist: return Array(library.doc.watchlist.prefix(3))
        case .films: return Array(library.watchedFilms.prefix(3))
        case .likes: return Array(library.doc.liked.reversed().prefix(3))
        case .lists: return library.doc.lists.compactMap(\.films.first)
        }
    }

    @ViewBuilder private var watchlist: some View {
        let list = sortByTitle ? library.doc.watchlist.sorted { $0.title < $1.title } : library.doc.watchlist
        if importer.running || importer.summary != nil { importStatus }
        if list.isEmpty {
            EmptyState(symbol: "clock", title: "Nothing saved yet", message: "Tap the clock on any film to save it for later.").padding(.top, 40)
            Button { importingWatchlist = true } label: {
                Label("Import my Letterboxd watchlist", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass).controlSize(.large).padding(.horizontal, 40)
            Text("On letterboxd.com open your Watchlist and choose Export Watchlist (or Settings → Data → Export and unzip it in Files), then pick watchlist.csv.")
                .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 40)
        } else {
            HStack {
                Text("\(list.count) film\(list.count == 1 ? "" : "s") to watch").font(.subheadline).foregroundStyle(Theme.dim)
                Spacer()
                GlassChip(prominent: true, action: { router.pickRandom(from: library) }) {
                    Label("Random pick", systemImage: "dice.fill")
                }
            }
            .padding(.horizontal, 20)
            Text("Tip: shake your phone or double-tap Library for a random pick too.")
                .font(.caption).foregroundStyle(Theme.dim).padding(.horizontal, 20)
            PosterGrid(films: list).padding(.horizontal, 16)
        }
    }

    /// Progress and result of a Letterboxd watchlist import.
    private var importStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: importer.running ? "arrow.down.circle" : "checkmark.circle.fill")
                    .foregroundStyle(importer.running ? Theme.accent : Theme.watch)
                    .symbolEffect(.pulse, isActive: importer.running)
                Text(importer.running ? "Importing from Letterboxd… \(importer.done)/\(importer.total)" : (importer.summary ?? ""))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !importer.running { Button("Done") { importer.summary = nil }.font(.subheadline.weight(.semibold)) }
            }
            if importer.running {
                ProgressView(value: Double(importer.done), total: Double(max(importer.total, 1))).tint(Theme.accent)
            }
            if !importer.running && !importer.unmatched.isEmpty {
                DisclosureGroup("\(importer.unmatched.count) couldn't be matched") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(importer.unmatched, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.dim) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
                .tint(.white)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var films: some View {
        let list = library.watchedFilms
        if list.isEmpty {
            EmptyState(symbol: "eye", title: "No films yet", message: "Films you watch, rate or log appear here.").padding(.top, 40)
        } else {
            Text("\(list.count) watched").font(.subheadline).foregroundStyle(Theme.dim).padding(.horizontal, 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(list) { f in
                    NavigationLink(value: f) {
                        VStack(spacing: 4) {
                            PosterView(film: f, corner: 6)
                            HStack(spacing: 3) {
                                SmallStars(rating: library.rating(f.id))
                                if library.isLiked(f.id) { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Theme.heart) }
                            }
                            .frame(height: 14)
                        }
                    }
                    .buttonStyle(.plain)
                    .filmContextMenu(f)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var likes: some View {
        let list = Array(library.doc.liked.reversed())
        if list.isEmpty {
            EmptyState(symbol: "heart", title: "No likes yet", message: "Tap the heart on films you love.").padding(.top, 40)
        } else {
            PosterGrid(films: list).padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var lists: some View {
        if library.doc.lists.isEmpty {
            EmptyState(symbol: "list.bullet.rectangle", title: "No lists yet", message: "Group films however you like — a ranking, a marathon, a mood.").padding(.top, 40)
            Button { router.sheet = .newList(nil) } label: { Label("Create a list", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).controlSize(.large).padding(.horizontal, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(library.doc.lists) { l in
                    NavigationLink(value: l) { ListCard(list: l) }.buttonStyle(.plain)
                        .contextMenu {
                            Button { router.sheet = .editList(l) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { library.deleteList(l) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Overlapping poster stack, like a fanned hand of cards.
struct ListCard: View {
    let list: FilmList
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .leading) {
                ForEach(Array(list.films.prefix(5).enumerated().reversed()), id: \.element.id) { i, f in
                    PosterView(film: f, width: 72, corner: 6, showTitleFallback: false)
                        .shadow(color: .black.opacity(0.8), radius: 6, x: 4)
                        .offset(x: CGFloat(i) * 52)
                }
                if list.films.isEmpty {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.card).frame(width: 72, height: 108)
                        .overlay(Image(systemName: "plus").foregroundStyle(Theme.dim))
                }
            }
            .frame(height: 108)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(list.name).font(.headline)
                    if !list.note.isEmpty { Text(list.note).font(.subheadline).foregroundStyle(Theme.dim).lineLimit(1) }
                }
                Spacer()
                Text("\(list.films.count) film\(list.films.count == 1 ? "" : "s")").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 22))
    }
}

struct ListDetailView: View {
    let listID: UUID
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @AppStorage("deckMode") private var deckMode = true

    private var list: FilmList? { library.doc.lists.first { $0.id == listID } }

    var body: some View {
        Group {
            if let list, deckMode && !list.films.isEmpty && !editing {
                FilmDeckScreen(films: list.films, action: .watchlist, deckMode: $deckMode)
                    .navigationTitle(list.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar { DeckToggle(deckMode: $deckMode) }
            } else if let list {
                List {
                    VStack(alignment: .leading, spacing: 6) {
                        if !list.note.isEmpty { Text(list.note).foregroundStyle(.white.opacity(0.8)) }
                        let seen = list.films.filter { library.isWatched($0.id) }.count
                        if !list.films.isEmpty {
                            ProgressView(value: Double(seen), total: Double(list.films.count)).tint(Theme.watch)
                            Text("You've seen \(seen) of \(list.films.count)").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    ForEach(Array(list.films.enumerated()), id: \.element.id) { i, f in
                        NavigationLink(value: f) {
                            HStack(spacing: 12) {
                                if list.ranked { Text("\(i + 1)").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Theme.dim).frame(width: 30) }
                                PosterView(film: f, width: 44, corner: 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.title).font(.body.weight(.semibold))
                                    HStack(spacing: 6) {
                                        Text(f.yearText).foregroundStyle(Theme.dim)
                                        if library.isWatched(f.id) { Image(systemName: "eye.fill").foregroundStyle(Theme.watch) }
                                        SmallStars(rating: library.rating(f.id))
                                    }.font(.subheadline)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in var l = list; l.films.move(fromOffsets: from, toOffset: to); library.updateList(l) }
                    .onDelete { idx in var l = list; l.films.remove(atOffsets: idx); library.updateList(l) }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(editing ? .active : .inactive))
                .navigationTitle(list.name)
                .toolbar {
                    if !list.films.isEmpty { DeckToggle(deckMode: $deckMode) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(editing ? "Done" : "Reorder") { withAnimation { editing.toggle() } }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { router.sheet = .editList(list) } label: { Label("Edit details", systemImage: "pencil") }
                            ShareLink(item: shareText(list))
                            Button(role: .destructive) { library.deleteList(list); dismiss() } label: { Label("Delete list", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
            } else {
                EmptyState(symbol: "list.bullet", title: "List not found", message: "It may have been deleted.")
            }
        }
        .ambientBackground(Array((list?.films ?? []).prefix(3)))
    }
}

private func shareText(_ list: FilmList) -> String {
    var lines = [list.name]
    for (i, f) in list.films.enumerated() {
        let marker = list.ranked ? "\(i + 1)." : "•"
        lines.append("\(marker) \(f.title) (\(f.yearText))")
    }
    return lines.joined(separator: "\n")
}

struct ListEditor: View {
    var seed: FilmRef? = nil
    var editing: FilmList? = nil
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""
    @State private var ranked = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name", text: $name)
                    TextField("Description (optional)", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Toggle("Ranked list", isOn: $ranked).tint(Theme.accent)
                } footer: { Text("Ranked lists show numbers and keep the order you set.") }
                if let seed { Section { Label("Starts with \(seed.title)", systemImage: "film") } }
            }
            .oledBackground()
            .navigationTitle(editing == nil ? "New list" : "Edit list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if var l = editing { l.name = n; l.note = note; l.ranked = ranked; library.updateList(l) }
                        else { library.createList(n, note: note, ranked: ranked, with: seed) }
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if let e = editing { name = e.name; note = e.note; ranked = e.ranked } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AddToListSheet: View {
    let film: FilmRef
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button { router.sheet = .newList(film) } label: { Label("New list with this film", systemImage: "plus.circle.fill").foregroundStyle(Theme.accent) }
                    .listRowBackground(Theme.card)
                ForEach(library.doc.lists) { l in
                    let on = l.films.contains { $0.id == film.id }
                    Button { library.toggle(film, in: l) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(l.name).foregroundStyle(.white)
                                Text("\(l.films.count) films").font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.accent : Theme.dim).font(.title3)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .oledBackground()
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
