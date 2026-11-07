import SwiftUI

/// Make a mood playlist: type a vibe (Apple Intelligence), tap mood chips, pick seed artists — or, without
/// Apple Intelligence, build a Mood Mix with the same scoring and manual sliders.
struct MoodBuilderSheet: View {
    var onMade: (MoodPlaylist) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryService.self) private var library
    @State private var vibe = ""
    @State private var moods: Set<String> = []
    @State private var genres: Set<String> = []
    @State private var seeds: Set<String> = []
    @State private var energy = 0.5
    @State private var length = 25.0
    @State private var useEra = false
    @State private var eraFrom = 2010.0
    @State private var eraTo = 2024.0
    @State private var working = false
    @State private var failure: String?
    private let ai = MoodAI.state

    private var topGenres: [String] {
        var counts: [String: Int] = [:]
        for s in library.snapshot.songs where !s.genre.isEmpty { counts[s.genre, default: 0] += s.playCount + 1 }
        return counts.sorted { $0.value > $1.value }.prefix(14).map(\.key)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick presets") {
                    ForEach(MoodPreset.allCases) { p in
                        Button(p.rawValue) { Task { await make(p.recipe, preset: p) } }.disabled(working)
                    }
                }
                aiSection
                Section("Moods") { ChipGrid(options: Moods.all, selection: $moods) }
                Section("Seed artists") { ChipGrid(options: library.stats.artists.prefix(16).map(\.name), selection: $seeds) }
                if ai != .available {
                    Section("Mood Mix") {
                        ChipGrid(options: topGenres, selection: $genres)
                        LabeledContent("Energy") { Slider(value: $energy, in: 0...1) }
                        Toggle("Only an era", isOn: $useEra)
                        if useEra {
                            Stepper("From \(Int(eraFrom))", value: $eraFrom, in: 1950...2030)
                            Stepper("To \(Int(eraTo))", value: $eraTo, in: 1950...2030)
                        }
                    }
                }
                Section {
                    Stepper("\(Int(length)) songs", value: $length, in: 15...40, step: 5)
                    Button(working ? "Making…" : "Make playlist", systemImage: "sparkles") { Task { await build() } }
                        .disabled(working || (vibe.isEmpty && moods.isEmpty && genres.isEmpty && seeds.isEmpty))
                } footer: {
                    if let failure { Text(failure).foregroundStyle(.orange) }
                    else { Text("Songs are chosen on this iPhone from your own library. Your library is never sent anywhere.") }
                }
            }
            .navigationTitle("New Mood Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
            .overlay { if working { ProgressView().controlSize(.large).padding(30).glassEffect(.regular, in: .rect(cornerRadius: 20)) } }
        }
    }

    @ViewBuilder private var aiSection: some View {
        switch ai {
        case .available:
            Section("Describe a vibe") {
                TextField("rainy late-night drive, a bit sad but hopeful", text: $vibe, axis: .vertical).lineLimit(2...4)
            }
        case .notEnabled:
            Section { Text("Turn on Apple Intelligence in Settings → Apple Intelligence & Siri to describe a vibe in your own words. Meanwhile, use the Mood Mix below.").font(.footnote) }
        case .notReady:
            Section { Text("The Apple Intelligence model is still downloading — try again later. You can use the Mood Mix below now.").font(.footnote) }
        case .notEligible, .unavailable:
            EmptyView()
        }
    }

    private func build() async {
        var recipe = MoodRecipe.blank
        recipe.moods = Array(moods)
        recipe.genres = Array(genres)
        recipe.seedArtists = Array(seeds)
        recipe.energy = energy
        recipe.length = Int(length)
        if useEra { recipe.eraFrom = Int(eraFrom); recipe.eraTo = Int(eraTo) }
        if ai == .available && !vibe.trimmingCharacters(in: .whitespaces).isEmpty {
            working = true
            do {
                recipe = try await MoodAI.recipe(vibe: vibe, chips: Array(moods), seeds: Array(seeds), genres: topGenres)
                recipe.length = Int(length)
            } catch {
                failure = "Apple Intelligence couldn't help this time (\(error.localizedDescription)). Made it from your choices instead."
            }
        } else {
            recipe.name = moods.first.map { "\($0) Mix" } ?? (seeds.first.map { "\($0) & More" } ?? "Mood Mix")
            recipe.summary = [moods.sorted().joined(separator: ", "), genres.sorted().joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        await make(recipe, preset: nil)
    }

    private func make(_ recipe: MoodRecipe, preset: MoodPreset?) async {
        working = true
        defer { working = false }
        if let p = await MoodPlaylistService.make(recipe, prompt: vibe, preset: preset, polish: preset == nil && !vibe.isEmpty, library: library) {
            onMade(p)
            dismiss()
        } else {
            failure = "Nothing matched yet — tag some songs with moods in their Song Passports, or loosen the choices."
        }
    }
}
