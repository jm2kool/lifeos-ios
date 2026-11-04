import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

/// Paste notes, pick a PDF, a photo or scan pages; AI writes the cards; you keep the ones you want.
struct GenerateCardsView: View {
    var deckID: UUID?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Deck> { !$0.trashed }, sort: \Deck.name) private var decks: [Deck]
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]

    @State private var notes = ""
    @State private var count = 15
    @State private var target: UUID?
    @State private var newDeckName = ""
    @State private var subjectID: UUID?
    @State private var drafts: [CardMaker.Draft] = []
    @State private var source: CardMaker.Source?
    @State private var note: String?
    @State private var working = false
    @State private var reading = false
    @State private var photo: PhotosPickerItem?
    @State private var pickingPDF = false
    @State private var scanning = false
    @State private var loaded = false

    var body: some View {
        Form {
            if drafts.isEmpty {
                Section {
                    TextField("Paste your notes here…", text: $notes, axis: .vertical)
                        .lineLimit(6...16)
                    HStack {
                        PhotosPicker(selection: $photo, matching: .images) { Label("Photo", systemImage: "photo") }
                        Spacer()
                        Button { pickingPDF = true } label: { Label("PDF", systemImage: "doc.richtext") }
                        Spacer()
                        if VNDocumentCameraViewController.isSupported {
                            Button { scanning = true } label: { Label("Scan", systemImage: "doc.viewfinder") }
                        }
                    }
                    .buttonStyle(.borderless)
                    if reading { HStack { ProgressView(); Text("Reading…").foregroundStyle(.secondary) } }
                } header: { Text("Notes") } footer: {
                    Text(CardMaker.onDeviceAvailable ? "Cards are written by Apple Intelligence on this iPhone." :
                            Auth.shared.signedIn ? "Cards are written by Lumen AI (your Supabase function)." :
                            "Without AI, lines like \"term: meaning\" become cards.")
                }
                Section("Cards") {
                    Stepper("About \(count) cards", value: $count, in: 5...60, step: 5)
                    Picker("Subject", selection: $subjectID) {
                        Text("None").tag(UUID?.none)
                        ForEach(subjects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Add to", selection: $target) {
                        Text("New deck").tag(UUID?.none)
                        ForEach(decks) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if target == nil { TextField("New deck name", text: $newDeckName) }
                }
                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            if working { ProgressView() } else { Image(systemName: "sparkles") }
                            Text(working ? "Writing cards…" : "Make cards")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(working || notes.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    if let source { Label("Made with \(source.rawValue)", systemImage: source == .rules ? "list.bullet" : "sparkles").font(.caption) }
                    if let note { Text(note).font(.caption).foregroundStyle(Theme.warn) }
                }
                Section("\(drafts.filter(\.keep).count) of \(drafts.count) selected") {
                    ForEach($drafts) { $d in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $d.keep) {
                                TextField("Front", text: $d.front, axis: .vertical).font(.subheadline.weight(.semibold))
                            }
                            TextField("Back", text: $d.back, axis: .vertical).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Start over", role: .destructive) { drafts = []; source = nil; note = nil }
                }
            }
        }
        .listRowBackground(Color.white.opacity(0.06))
        .scrollContentBackground(.hidden)
        .backdrop([Theme.instinct, Theme.accent])
        .navigationTitle("Make cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            if !drafts.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(drafts.filter(\.keep).count)", action: save).buttonStyle(.glassProminent)
                        .disabled(!drafts.contains(where: \.keep))
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            target = deckID
            subjectID = store.find(Deck.self, deckID)?.subjectID
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                reading = true
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    append(await TextExtractor.image(img))
                }
                reading = false
                photo = nil
            }
        }
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf, .plainText]) { result in
            guard case .success(let url) = result else { return }
            if url.pathExtension.lowercased() == "pdf" { append(TextExtractor.pdf(url)) } else {
                let access = url.startAccessingSecurityScopedResource()
                append((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                if access { url.stopAccessingSecurityScopedResource() }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                Task {
                    reading = true
                    for img in images { append(await TextExtractor.image(img)) }
                    reading = false
                }
            }
            .ignoresSafeArea()
        }
    }

    private func append(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { note = "Couldn't find any text there."; return }
        notes = notes.isEmpty ? t : notes + "\n\n" + t
    }

    private func generate() async {
        working = true
        note = nil
        let subject = subjects.first { $0.id == subjectID }?.name
        let r = await CardMaker.make(from: notes, count: count, subject: subject)
        drafts = r.cards
        source = r.source
        note = r.note
        if drafts.isEmpty && note == nil { note = "No cards came back. Try more detailed notes." }
        working = false
        if !drafts.isEmpty { Haptics.success() }
    }

    private func save() {
        var deck = store.find(Deck.self, target)
        if deck == nil {
            let d = Deck(id: UUID())
            let fallback = subjects.first { $0.id == subjectID }.map { "\($0.name) cards" } ?? "New deck"
            d.name = newDeckName.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : newDeckName
            d.subjectID = subjectID
            store.insert(d)
            deck = d
        }
        guard let deck else { return }
        var added = 0
        for (i, d) in drafts.enumerated() where d.keep {
            let c = Card(id: UUID())
            c.deckID = deck.id
            c.front = d.front.trimmingCharacters(in: .whitespacesAndNewlines)
            c.back = d.back.trimmingCharacters(in: .whitespacesAndNewlines)
            c.dueAt = Date()
            store.insert(c)
            c.createdAt = Date().addingTimeInterval(Double(i) / 1000)   // keeps them in order
            added += 1
        }
        store.save()
        store.show("Added \(added) cards to \(deck.name)", symbol: "rectangle.stack.badge.plus")
        dismiss()
    }
}

/// The system document scanner, for photographing pages of notes.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
    }
}
