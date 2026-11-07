import SwiftUI

/// Settings. Most options from SPEC §6.17 arrive with their features; for now: library tools, the spike lab and about.
struct SettingsView: View {
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var cleared = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    LabeledContent("Songs", value: library.snapshot.songs.count.grouped)
                    LabeledContent("Albums", value: library.snapshot.albums.count.grouped)
                    if library.hasLoaded {
                        LabeledContent("Last scan", value: "\(library.snapshot.scannedAt.formatted(date: .omitted, time: .shortened)) · \(library.snapshot.scanDuration.formatted(.units(allowed: [.seconds, .milliseconds])))")
                    }
                    Button(library.isLoading ? "Scanning…" : "Rescan library") { Task { await library.refresh() } }
                        .disabled(library.isLoading)
                    Button(cleared ? "Artwork cache cleared" : "Clear artwork cache") {
                        ArtworkCache.shared.clear()
                        cleared = true
                    }
                }
                Section {
                    NavigationLink("Spike lab") { SpikeHomeView() }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("The Phase 0 tests: lock screen artwork, Apple Intelligence, Deezer photos, playback and Instagram video. Copy the report when you've run them.")
                }
                Section("About") {
                    LabeledContent(AppBrand.name, value: version)
                    Text("Your notes on the music. Reads your Apple Music library and never changes it. Artist photos from Deezer.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
            }
        }
    }
}

#Preview { SettingsView().environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark) }
