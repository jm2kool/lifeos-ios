import SwiftUI
import UniformTypeIdentifiers

/// Settings (SPEC §6.17): Vinyl Mode, Living Covers, Low Power, lyrics, needle sounds, recap notifications,
/// rebuild stats, backup, test data, diagnostics and about.
struct SettingsView: View {
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("vinylMode") private var vinylMode = false
    @AppStorage("livingCovers") private var livingCovers = true
    @AppStorage("livingCoverStyle") private var coverStyle = LivingCoverRenderer.Style.drift.rawValue
    @AppStorage("respectLowPower") private var respectLowPower = false
    @AppStorage("animatedLockForLibrary") private var lockForLibrary = true
    @AppStorage("lyricsSource") private var lyricsSource = "lrclib"
    @AppStorage("needleSounds") private var needleSounds = true
    @AppStorage("recapNotifications") private var recapNotifications = false
    @AppStorage("brandName") private var brandName = ""
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var message: String?
    @State private var cacheSize = ""

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message { Section { Text(message).font(.footnote) } }
                Section("Listening") {
                    Toggle("Vinyl Mode", isOn: $vinylMode)
                    Toggle("Needle sounds", isOn: $needleSounds).disabled(!vinylMode)
                    Picker("Lyrics", selection: $lyricsSource) {
                        Text("LRCLIB").tag("lrclib")
                        Text("Off").tag("off")
                    }
                }
                Section {
                    Toggle("Living Covers", isOn: $livingCovers)
                    Picker("Style", selection: $coverStyle) {
                        ForEach(LivingCoverRenderer.Style.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    .disabled(!livingCovers)
                    Toggle("Respect Low Power Mode", isOn: $respectLowPower)
                    Toggle("Animated lock screen for Apple Music songs", isOn: $lockForLibrary)
                    LabeledContent("Living Cover cache", value: cacheSize)
                    Button("Clear Living Cover cache") { LivingCoverRenderer.clearCache(); updateCache() }
                } header: { Text("Covers") } footer: {
                    Text("Covers keep moving in Low Power Mode inside the app unless you turn on Respect Low Power Mode. On the lock screen iOS always shows a still picture in Low Power Mode. Animated lock screen artwork for Apple Music songs is best effort; it always works for mixtapes.")
                }
                Section("Recaps") {
                    Toggle("Monday morning recap notification", isOn: $recapNotifications)
                        .onChange(of: recapNotifications) { _, on in Task { if on, !(await RecapNotifications.setEnabled(true)) { recapNotifications = false } else if !on { _ = await RecapNotifications.setEnabled(false) } } }
                    if let b = SnapshotService.shared.baselineDate {
                        LabeledContent("Recording since", value: b.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Section("Library") {
                    LabeledContent("Songs", value: library.snapshot.songs.count.grouped)
                    LabeledContent("Albums", value: library.snapshot.albums.count.grouped)
                    if library.hasLoaded {
                        LabeledContent("Last scan", value: "\(library.snapshot.scannedAt.formatted(date: .omitted, time: .shortened)) · \(library.snapshot.scanDuration.formatted(.units(allowed: [.seconds, .milliseconds])))")
                    }
                    Button(library.isLoading ? "Rebuilding…" : "Rebuild stats") { Task { ArtworkCache.shared.clear(); await library.refresh() } }
                        .disabled(library.isLoading)
                }
                Section {
                    Button("Export backup (JSON)", systemImage: "square.and.arrow.up") {
                        do { exportURL = try BackupService.export() } catch { message = "Export failed: \(error.localizedDescription)" }
                    }
                    if let exportURL { ShareLink("Save or send the backup", item: exportURL) }
                    Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
                } header: { Text("Backup") } footer: {
                    Text("Passports, rankings, pins, editions, mixtape details and mood playlists. Mixtape audio files stay in the Files app under \(AppBrand.name).")
                }
                Section {
                    NavigationLink("Spike lab") { SpikeHomeView() }
                    Button("Add two weeks of test plays") { DebugSeeder.seed(library.snapshot); message = "Added test plays. See Recaps." }
                    Button("Remove test plays", role: .destructive) { DebugSeeder.remove(); message = "Removed test plays." }
                    if let err = Store.openError { Text("Storage problem: \(err)").font(.footnote).foregroundStyle(.orange) }
                } header: { Text("Diagnostics") } footer: {
                    Text("The spike lab re-runs the Phase 0 checks. Test plays are made-up recaps data, marked so they can be removed.")
                }
                Section("About") {
                    HStack(spacing: 14) {
                        Image("Logo").resizable().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading) { Text(AppBrand.name).font(.serif(22)); Text(version).font(.caption).foregroundStyle(.secondary) }
                    }
                    TextField("App name (LINER.)", text: $brandName)
                    Text("Your notes on the music. Inspired by @sakisgraphics' MONO. concept and MD Vinyl. Reads your Apple Music library and never changes it, except a mood playlist you save. Artist photos from Deezer, lyrics from LRCLIB.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                do { message = try BackupService.restore(url); library.reloadPersonalRatings() } catch { message = "Couldn't read that backup: \(error.localizedDescription)" }
            }
            .onAppear { updateCache() }
            .onChange(of: coverStyle) { PlaybackCoordinator.shared?.nowPlaying.animated.reset() }
            .onChange(of: livingCovers) { PlaybackCoordinator.shared?.nowPlaying.animated.reset() }
        }
    }

    private func updateCache() { cacheSize = ByteCountFormatter.string(fromByteCount: LivingCoverRenderer.cacheSize, countStyle: .file) }
}

#Preview { SettingsView().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
