import SwiftUI

/// Song Passport (SPEC §6.8): rating, moods, notes, connection, Song DNA, favourite moments, saved lyric lines.
struct SongPassportSheet: View {
    let item: QueueItem
    @Environment(\.dismiss) private var dismiss
    @State private var note: SongNote?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let note {
                    SongPassportContent(item: item, note: note)
                } else {
                    ProgressView().padding(60)
                }
            }
            .background(Palette.background)
            .navigationTitle("Song Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { SongPassportShare.button(item: item) }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { note = Store.shared.songNoteOrNew(for: item) }
        .onDisappear { if let note { Store.shared.dropIfEmpty(note) } }
    }
}

/// The passport's sections, bound to the note.
struct SongPassportContent: View {
    let item: QueueItem
    @Bindable var note: SongNote
    @Environment(LibraryService.self) private var library
    @State private var customMood = ""
    @State private var addingMood = false

    private var allMoods: [String] { Moods.all + note.moods.filter { !Moods.all.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            section("My Rating") {
                HeartRating(rating: Binding(get: { note.rating }, set: { note.rating = $0; touch() }), size: 28)
            }
            section("Moods") {
                ChipGrid(options: allMoods, selection: Binding(get: { Set(note.moods) }, set: { note.moods = allMoods.filter($0.contains); touch() }))
                Button("+ Custom", systemImage: "plus") { addingMood = true }.font(.footnote).buttonStyle(.glass)
            }
            section("My Notes") {
                TextField("What this song is to you", text: Binding(get: { note.notes }, set: { note.notes = $0; touch() }), axis: .vertical)
                    .lineLimit(3...10).textFieldStyle(.plain).padding(12).background(Palette.placeholder, in: RoundedRectangle(cornerRadius: 12))
            }
            section("My Connection") {
                TextField("A person, a place, a summer…", text: Binding(get: { note.connection }, set: { note.connection = $0; touch() }), axis: .vertical)
                    .lineLimit(2...6).textFieldStyle(.plain).padding(12).background(Palette.placeholder, in: RoundedRectangle(cornerRadius: 12))
            }
            section("Song DNA") { SongDNA(item: item, song: item.song.flatMap { library.snapshot.songs([$0.id]).first } ?? item.song) }
            section("My Favorite Moments") { FavoriteMoments(item: item, note: note) }
            if !note.lyricLines.isEmpty {
                section("Saved Lyric Lines") {
                    ForEach(note.lyricLines, id: \.self) { line in
                        Text("“\(line)”").font(.serif(18)).italic()
                            .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { note.lyricLines.removeAll { $0 == line }; touch() } }
                    }
                }
            }
        }
        .padding(16)
        .alert("Custom mood", isPresented: $addingMood) {
            TextField("Mood", text: $customMood)
            Button("Add") {
                let m = customMood.trimmingCharacters(in: .whitespaces)
                if !m.isEmpty && !note.moods.contains(m) { note.moods.append(m); touch() }
                customMood = ""
            }
            Button("Cancel", role: .cancel) { customMood = "" }
        }
    }

    private func touch() { note.updatedAt = .now }

    private var header: some View {
        HStack(spacing: 14) {
            QueueItemArtwork(item: item, cornerRadius: 12).frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.serif(24)).lineLimit(2)
                Text(item.artist).linerLabel()
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
    }
}

/// The song's facts, from the library.
struct SongDNA: View {
    let item: QueueItem
    let song: Song?

    var body: some View {
        Card {
            if let s = song {
                row("Album", s.albumTitle)
                row("Release date", s.releaseDate?.formatted(date: .long, time: .omitted))
                row("Duration", s.duration.trackTime)
                row("Genre", s.genre)
                row("Composer", s.composer)
                row("Album artist", s.albumArtist)
                row("Track", s.trackNumber > 0 ? "\(s.trackNumber)" : nil)
                row("Plays", s.playCount.grouped)
                row("Last played", s.lastPlayed?.formatted(date: .abbreviated, time: .shortened))
                row("Date added", s.dateAdded.formatted(date: .abbreviated, time: .omitted))
            } else {
                row("Album", item.albumTitle)
                row("Duration", item.duration.trackTime)
                row("Source", "Mixtape (imported file)")
            }
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).linerLabel(size: 10)
                Spacer()
                Text(value).font(.subheadline).multilineTextAlignment(.trailing)
            }
        }
    }
}

#Preview {
    SongPassportSheet(item: .library(PreviewData.snapshot.songs[0]))
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
