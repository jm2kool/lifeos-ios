import SwiftUI
import SwiftData
import PhotosUI

struct CardsView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Deck> { !$0.trashed }, sort: \Deck.name) private var decks: [Deck]
    @Query(filter: #Predicate<Card> { !$0.trashed }) private var cards: [Card]
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @State private var newDeck = false

    var body: some View {
        let due = cards.isEmpty ? 0 : store.dueCards().count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                reviewHero(due: due)
                HStack {
                    SectionTitle("Decks", symbol: "square.stack.3d.up")
                    Button { router.sheet = .generateCards(nil) } label: { Label("Make with AI", systemImage: "sparkles") }
                        .buttonStyle(.glass).controlSize(.small)
                }
                if decks.isEmpty {
                    EmptyCard(symbol: "rectangle.stack.badge.plus", title: "No decks yet",
                              text: "Make a deck for a subject or chapter, or paste notes and let AI write the cards.")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(decks) { d in
                        NavigationLink(value: d.id) { DeckTile(deck: d, cards: cards.filter { $0.deckID == d.id }) }
                            .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
        .backdrop(subjects.map { Color(hex: $0.color) } + [Theme.instinct])
        .navigationTitle("Cards")
        .navigationDestination(for: UUID.self) { id in
            if let d = store.find(Deck.self, id) { DeckDetail(deck: d) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { router.sheet = .settings } label: { Image(systemName: "gearshape") } }
            ToolbarItem(placement: .topBarTrailing) { Button { newDeck = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $newDeck) { NavigationStack { DeckEditor(deck: nil) }.preferredColorScheme(.dark) }
    }

    private func reviewHero(due: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's review").font(.caption.weight(.heavy)).foregroundStyle(Theme.instinct)
            Text(due == 0 ? "You're all caught up" : "\(due) card\(due == 1 ? "" : "s") ready").font(.title2.weight(.bold))
            Text(due == 0 ? "New reviews appear as cards come due." : "About \(max(1, due * 8 / 60)) min · spaced repetition (FSRS)")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { router.openReview() } label: { Label("Start review", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(Theme.instinct).controlSize(.large)
                .disabled(due == 0)
        }
        .glassCard(tint: Theme.instinct, radius: 28, padding: 18)
    }
}

struct DeckTile: View {
    var deck: Deck
    var cards: [Card]
    @Environment(Store.self) private var store

    var body: some View {
        let s = store.subject(deck.subjectID)
        let color = Color(hex: s?.color ?? "#B48CFF")
        let due = cards.filter { !$0.isNew && $0.dueAt <= Date() }.count
        let fresh = cards.filter(\.isNew).count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: s?.icon ?? "rectangle.stack").foregroundStyle(color)
                Spacer()
                if deck.byInstinct { InstinctBadge(compact: true) }
            }
            Text(deck.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
            Text(store.find(Chapter.self, deck.chapterID)?.shortTitle ?? s?.name ?? "No subject").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                Label("\(cards.count)", systemImage: "rectangle.on.rectangle").font(.caption2)
                if due > 0 { Label("\(due)", systemImage: "clock.badge.exclamationmark").font(.caption2).foregroundStyle(Theme.warn) }
                if fresh > 0 { Label("\(fresh)", systemImage: "sparkle").font(.caption2).foregroundStyle(Theme.accent) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .glassCard(tint: color, radius: 22, padding: 14, interactive: true)
    }
}

// MARK: - Deck

struct DeckDetail: View {
    @Bindable var deck: Deck
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { !$0.trashed }) private var allCards: [Card]
    @State private var editing: Card?
    @State private var adding = false
    @State private var editDeck = false
    @State private var search = ""

    var body: some View {
        let cards = allCards.filter { $0.deckID == deck.id }
            .filter { search.isEmpty || $0.front.localizedCaseInsensitiveContains(search) || $0.back.localizedCaseInsensitiveContains(search) }
            .sorted { $0.createdAt < $1.createdAt }
        let due = store.dueCards(deck: deck.id).count
        List {
            Section {
                HStack(spacing: 10) {
                    Button { router.openReview(deck: deck.id) } label: { Label("Review \(due)", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent).disabled(due == 0)
                    Button { router.sheet = .generateCards(deck.id) } label: { Label("AI", systemImage: "sparkles") }
                        .buttonStyle(.glass)
                    Button { adding = true } label: { Label("Card", systemImage: "plus") }
                        .buttonStyle(.glass)
                }
                .listRowBackground(Color.clear)
            }
            Section("\(cards.count) cards") {
                ForEach(cards) { c in
                    Button { editing = c } label: { CardRow(card: c) }.buttonStyle(.plain)
                }
                .onDelete { idx in for i in idx { cards[i].trashed = true; cards[i].touch() }; store.save() }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .searchable(text: $search, prompt: "Search cards")
        .backdrop([Color(hex: store.subject(deck.subjectID)?.color ?? "#B48CFF")])
        .navigationTitle(deck.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit deck", systemImage: "pencil") { editDeck = true }
                    Button("Reset progress", systemImage: "arrow.counterclockwise") {
                        for c in cards { c.memory = FSRS.Memory(); c.dueAt = Date(); c.touch() }
                        store.save()
                    }
                    Button("Delete deck", systemImage: "trash", role: .destructive) {
                        for c in cards { c.trashed = true; c.touch() }
                        store.remove(deck)
                        dismiss()
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(item: $editing) { c in NavigationStack { CardEditor(card: c, deckID: deck.id) }.preferredColorScheme(.dark) }
        .sheet(isPresented: $adding) { NavigationStack { CardEditor(card: nil, deckID: deck.id) }.preferredColorScheme(.dark) }
        .sheet(isPresented: $editDeck) { NavigationStack { DeckEditor(deck: deck) }.preferredColorScheme(.dark) }
    }
}

struct CardRow: View {
    var card: Card
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                MathText(text: card.front, font: .subheadline.weight(.semibold)).lineLimit(2)
                Spacer()
                if card.byInstinct { InstinctBadge(compact: true) }
                if card.frontImage != nil || card.backImage != nil { Image(systemName: "photo").font(.caption).foregroundStyle(.secondary) }
            }
            MathText(text: card.back, font: .caption).foregroundStyle(.secondary).lineLimit(2)
            Text(card.isNew ? "New" : (card.dueAt <= Date() ? "Due now" : "Due \(Fmt.day(card.dueAt))"))
                .font(.caption2).foregroundStyle(card.isNew ? Theme.accent : card.dueAt <= Date() ? Theme.warn : .secondary)
        }
        .padding(.vertical, 2)
    }
}

struct DeckEditor: View {
    var deck: Deck?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @Query(filter: #Predicate<Chapter> { !$0.trashed }, sort: \Chapter.sort) private var chapters: [Chapter]
    @State private var name = ""
    @State private var subjectID: UUID?
    @State private var chapterID: UUID?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Deck name", text: $name)
                Picker("Subject", selection: $subjectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(subjects) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Chapter", selection: $chapterID) {
                    Text("None").tag(UUID?.none)
                    ForEach(chapters.filter { $0.subjectID == subjectID }) { Text($0.displayTitle).tag(Optional($0.id)) }
                }
                .disabled(subjectID == nil)
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .backdrop([Theme.instinct])
        .navigationTitle(deck == nil ? "New deck" : "Edit deck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let d = deck ?? Deck(id: UUID())
                    d.name = name.trimmingCharacters(in: .whitespaces)
                    d.subjectID = subjectID
                    d.chapterID = chapterID
                    if deck == nil { store.insert(d) } else { d.touch() }
                    store.save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = deck?.name ?? ""
            subjectID = deck?.subjectID
            chapterID = deck?.chapterID
        }
    }
}

// MARK: - Card editor

struct CardEditor: View {
    var card: Card?
    var deckID: UUID
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var front = ""
    @State private var back = ""
    @State private var frontImage: String?
    @State private var backImage: String?
    @State private var frontPick: PhotosPickerItem?
    @State private var backPick: PhotosPickerItem?
    @State private var loaded = false
    @State private var addAnother = false

    var body: some View {
        Form {
            Section {
                TextField("Front — a question or prompt", text: $front, axis: .vertical).lineLimit(2...6)
                if front.contains("$") { MathText(text: front, font: .body) }
                imageRow(path: $frontImage, pick: $frontPick)
            } header: { Text("Front") }
            Section {
                TextField("Back — the answer", text: $back, axis: .vertical).lineLimit(2...8)
                if back.contains("$") { MathText(text: back, font: .body) }
                imageRow(path: $backImage, pick: $backPick)
            } header: { Text("Back") } footer: {
                Text("Write formulas between dollar signs: $v = u + at$, $H_2O$, $\\frac{1}{2}mv^2$, $\\alpha \\leq \\beta$.")
            }
            if card == nil {
                Section { Toggle("Add another after saving", isOn: $addAnother) }
            }
        }
        .scrollContentBackground(.hidden)
        .backdrop([Theme.instinct])
        .navigationTitle(card == nil ? "New card" : "Edit card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(front.trimmingCharacters(in: .whitespaces).isEmpty && frontImage == nil)
            }
        }
        .onAppear {
            guard !loaded, let card else { loaded = true; return }
            loaded = true
            front = card.front; back = card.back; frontImage = card.frontImage; backImage = card.backImage
        }
        .onChange(of: frontPick) { _, item in Task { frontImage = await Files.importPhoto(item, folder: "cards") ?? frontImage } }
        .onChange(of: backPick) { _, item in Task { backImage = await Files.importPhoto(item, folder: "cards") ?? backImage } }
    }

    private func imageRow(path: Binding<String?>, pick: Binding<PhotosPickerItem?>) -> some View {
        HStack {
            if let p = path.wrappedValue {
                StoredImage(path: p).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 10))
                Button("Remove", role: .destructive) { path.wrappedValue = nil }
            }
            Spacer()
            PhotosPicker(selection: pick, matching: .images) {
                Label(path.wrappedValue == nil ? "Add image" : "Change", systemImage: "photo")
            }
        }
    }

    private func save() {
        let c = card ?? Card(id: UUID())
        c.front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        c.back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        c.frontImage = frontImage
        c.backImage = backImage
        c.deckID = card?.deckID ?? deckID
        if card == nil { c.dueAt = Date(); store.insert(c) } else { c.touch() }
        store.save()
        Haptics.success()
        if card == nil && addAnother {
            front = ""; back = ""; frontImage = nil; backImage = nil
        } else {
            dismiss()
        }
    }
}

// MARK: - Review

/// One card at a time: tap to turn it over, then Again / Hard / Good / Easy.
struct ReviewSession: View {
    var deckID: UUID?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var shownAt = Date()
    @State private var reviewed = 0
    @State private var again = 0
    @State private var loaded = false
    @Namespace private var ns

    var body: some View {
        let card = index < queue.count ? queue[index] : nil
        let color = Color(hex: store.subject(store.find(Deck.self, card?.deckID)?.subjectID)?.color ?? "#B48CFF")
        NavigationStack {
            VStack(spacing: 18) {
                ProgressBar(progress: queue.isEmpty ? 1 : Double(index) / Double(queue.count), color: color)
                    .padding(.horizontal)
                if let card {
                    cardFace(card, color: color)
                        .id(card.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    Spacer(minLength: 0)
                    buttons(card)
                } else {
                    done
                }
            }
            .padding(.vertical)
            .backdrop([color, Theme.instinct])
            .navigationTitle(card == nil ? "Review" : "\(index + 1) of \(queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            queue = store.dueCards(deck: deckID)
            shownAt = Date()
        }
    }

    private func cardFace(_ card: Card, color: Color) -> some View {
        Button {
            withAnimation(.spring(duration: 0.45)) { flipped.toggle() }
            Haptics.tap()
        } label: {
            VStack(spacing: 16) {
                if card.byInstinct { HStack { Spacer(); InstinctBadge(compact: true) } }
                Spacer(minLength: 0)
                if let img = card.frontImage { StoredImage(path: img).frame(maxHeight: 180).clipShape(.rect(cornerRadius: 14)) }
                MathText(text: card.front, font: .title2.weight(.semibold)).multilineTextAlignment(.center)
                if flipped {
                    Divider().overlay(color)
                    if let img = card.backImage { StoredImage(path: img).frame(maxHeight: 180).clipShape(.rect(cornerRadius: 14)) }
                    MathText(text: card.back, font: .title3).multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text("Tap to show the answer").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
            .padding(24)
            .glassEffect(.regular.tint(color.opacity(0.2)).interactive(), in: .rect(cornerRadius: 32))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func buttons(_ card: Card) -> some View {
        let preview = FSRS(retention: store.prefs.desiredRetention).preview(card.memory)
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if flipped {
                    ForEach(Rating.allCases) { r in
                        Button { answer(card, r) } label: {
                            VStack(spacing: 2) {
                                Text(r.label).font(.subheadline.weight(.semibold))
                                Text(FSRS.shortInterval((preview[r]?.due ?? Date()).timeIntervalSinceNow)).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .tint(tint(r))
                        .glassEffectID(r.rawValue, in: ns)
                    }
                } else {
                    Button { withAnimation(.spring(duration: 0.45)) { flipped = true } } label: {
                        Text("Show answer").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .glassEffectID(3, in: ns)
                }
            }
            .controlSize(.large)
            .padding(.horizontal)
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.good).symbolEffect(.bounce, value: reviewed)
            Text(reviewed == 0 ? "Nothing due right now" : "Review done").font(.title2.weight(.bold))
            if reviewed > 0 {
                Text("\(reviewed) reviews · \(again) to see again soon").foregroundStyle(.secondary)
            }
            Button("Finish") { dismiss() }.buttonStyle(.glassProminent).controlSize(.large)
            Spacer()
        }
    }

    private func answer(_ card: Card, _ rating: Rating) {
        store.review(card, rating, duration: Date().timeIntervalSince(shownAt))
        reviewed += 1
        if rating == .again {
            again += 1
            queue.append(card)   // seen again before the end of this session
        }
        if rating == .easy || rating == .good { Haptics.success() } else { Haptics.tap() }
        withAnimation(.spring(duration: 0.4)) {
            flipped = false
            index += 1
        }
        shownAt = Date()
    }

    private func tint(_ r: Rating) -> Color {
        switch r {
        case .again: return Theme.bad
        case .hard: return Theme.warn
        case .good: return Theme.good
        case .easy: return Theme.accent
        }
    }
}
