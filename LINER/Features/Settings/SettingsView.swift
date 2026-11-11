import SwiftUI
import UniformTypeIdentifiers

/// Settings (SPEC §6.17): Vinyl Mode, Living Covers, Low Power, lyrics, needle sounds, recap notifications,
/// rebuild stats, backup, updates, test data, diagnostics and about.
struct SettingsView: View {
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @AppStorage("musicConnected") private var connected = true
    @State private var recalibrating = false
    @AppStorage("vinylMode") private var vinylMode = false
    @AppStorage("livingCovers") private var livingCovers = true
    @AppStorage("livingCoverStyle") private var coverStyle = LivingCoverRenderer.Style.drift.rawValue
    @AppStorage("respectLowPower") private var respectLowPower = false
    @AppStorage("animatedLockForLibrary") private var lockForLibrary = true
    @AppStorage("ownPlayerForFiles") private var ownPlayer = true
    @AppStorage("lyricsSource") private var lyricsSource = "lrclib"
    @AppStorage("needleSounds") private var needleSounds = true
    @AppStorage("liveLyrics") private var liveLyrics = true
    @AppStorage("openPlayerOnPlay") private var openPlayerOnPlay = true
    @AppStorage("albumLogos") private var albumLogos = true
    @AppStorage("recapNotifications") private var recapNotifications = false
    @AppStorage("brandName") private var brandName = ""
    @AppStorage("groupAlbumEditions") private var groupEditions = true
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
                Section {
                    Toggle("Vinyl Mode", isOn: $vinylMode)
                    Toggle("Needle sounds", isOn: $needleSounds).disabled(!vinylMode)
                    Toggle("Open the player when a song starts", isOn: $openPlayerOnPlay)
                    Toggle("Live lyrics on the Lock Screen", isOn: $liveLyrics)
                        .onChange(of: liveLyrics) { _, on in if !on { LyricsLiveActivityController.shared.stop() } }
                    NavigationLink("Live lyrics log") { LiveLyricsLogView() }
                    Picker("Lyrics", selection: $lyricsSource) {
                        Text("LRCLIB").tag("lrclib")
                        Text("Off").tag("off")
                    }
                } header: { Text("Listening") } footer: {
                    Text("With Vinyl Mode on, Home becomes your record crate and the Library shows albums as a crate.")
                }
                Section("Artists") {
                    NavigationLink("Artist titles") { ArtistTitlesSettings() }
                }
                Section {
                    Toggle("Living Covers", isOn: $livingCovers)
                    Toggle("Album title logos", isOn: $albumLogos)
                        .onChange(of: albumLogos) { CustomAlbumLogos.shared.refresh() }
                    Picker("Style", selection: $coverStyle) {
                        ForEach(LivingCoverRenderer.Style.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    .disabled(!livingCovers)
                    Toggle("Respect Low Power Mode", isOn: $respectLowPower)
                    Toggle("Play my own files in LINER.", isOn: $ownPlayer)
                    Toggle("Try animated lock screen for Apple Music songs", isOn: $lockForLibrary)
                    LabeledContent("Living Cover cache", value: cacheSize)
                    Button("Clear Living Cover cache") { LivingCoverRenderer.clearCache(); updateCache() }
                } header: { Text("Covers") } footer: {
                    Text("Covers keep moving in Low Power Mode inside the app unless you turn on Respect Low Power Mode. On the lock screen iOS always shows a still picture in Low Power Mode. Full-screen lock screen artwork works for mixtapes and for songs without copy protection (iTunes purchases, synced or ripped music) when “Play my own files in LINER.” is on; those plays are added to your stats by LINER. Streaming Apple Music songs are played by iOS itself, which keeps its standard lock screen.")
                }
                Section("Recaps") {
                    Toggle("Monday morning recap notification", isOn: $recapNotifications)
                        .onChange(of: recapNotifications) { _, on in Task { if on, !(await RecapNotifications.setEnabled(true)) { recapNotifications = false } else if !on { _ = await RecapNotifications.setEnabled(false) } } }
                    if let b = SnapshotService.shared.baselineDate {
                        LabeledContent("Recording since", value: b.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Section {
                    Toggle("Group album editions", isOn: $groupEditions)
                        .onChange(of: groupEditions) { Task { await library.refresh() } }
                    if !AlbumGroups.isEmpty {
                        Button("Forget the albums I grouped", role: .destructive) {
                            AlbumGroups.reset()
                            message = "Your own album groups are gone; albums are grouped by name again."
                            Task { await library.refresh() }
                        }
                    }
                    LabeledContent("Songs", value: library.snapshot.songs.count.grouped)
                    LabeledContent("Albums", value: library.snapshot.albums.count.grouped)
                    if library.hasLoaded {
                        LabeledContent("Last scan", value: "\(library.snapshot.scannedAt.formatted(date: .omitted, time: .shortened)) · \(library.snapshot.scanDuration.formatted(.units(allowed: [.seconds, .milliseconds])))")
                    }
                    Button(library.isLoading ? "Rebuilding…" : "Rebuild stats") { Task { ArtworkCache.shared.clear(); await library.refresh() } }
                        .disabled(library.isLoading)
                } header: { Text("Library") } footer: {
                    Text("With Group album editions on, “WILD” and “WILD (Deluxe)” show as one album led by the biggest edition, with any extra songs added. Group other versions yourself (or separate them) from an album's menu: Group Versions.")
                }
                Section {
                    Button(recalibrating ? "Recalibrating…" : "Recalibrate Apple Music", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await recalibrate() }
                    }
                    .disabled(recalibrating || library.isLoading)
                    Button("Show the connect screen again", systemImage: "music.note") { connected = false; dismiss() }
                } header: { Text("Apple Music") } footer: {
                    Text("If songs stop playing from Apple Music (for example after reinstalling \(AppBrand.name)), recalibrate: it asks for access again, resets the player and rescans your library.")
                }
                Section {
                    Button("Export backup (JSON)", systemImage: "square.and.arrow.up") {
                        do { exportURL = try BackupService.export() } catch { message = "Export failed: \(error.localizedDescription)" }
                    }
                    if let exportURL { ShareLink("Save or send the backup", item: exportURL) }
                    Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
                } header: { Text("Backup") } footer: {
                    Text("Passports, rankings, pins, editions, mixtape details, mood playlists, album groups, vinyl sides, the Listening Room shelf and artist posters and your album logos. Mixtape audio files stay in the Files app under \(AppBrand.name).")
                }
                Section {
                    NavigationLink("Spike lab") { SpikeHomeView() }
                    Button("Add two weeks of test plays") { DebugSeeder.seed(library.snapshot); message = "Added test plays. See Recaps." }
                    Button("Remove test plays", role: .destructive) { DebugSeeder.remove(); message = "Removed test plays." }
                    if let err = Store.openError { Text("Storage problem: \(err)").font(.footnote).foregroundStyle(.orange) }
                } header: { Text("Diagnostics") } footer: {
                    Text("The spike lab re-runs the Phase 0 checks. Test plays are made-up recaps data, marked so they can be removed.")
                }
                Section {
                    NavigationLink { UpdateView() } label: {
                        LabeledContent("Update \(AppBrand.name)", value: AppUpdater.shared.isAvailable ? "New build" : "")
                    }
                } header: { Text("Updates") } footer: {
                    Text("Checks GitHub for a newer build and installs it on the phone with SideStore or AltStore, so you don't need Sideloadly for every update.")
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
                do { message = try BackupService.restore(url); library.reloadPersonalRatings(); Task { await library.refresh() } } catch { message = "Couldn't read that backup: \(error.localizedDescription)" }
            }
            .onAppear { updateCache() }
            .onChange(of: coverStyle) { PlaybackCoordinator.shared?.nowPlaying.animated.reset() }
            .onChange(of: livingCovers) { PlaybackCoordinator.shared?.nowPlaying.animated.reset() }
        }
    }

    private func recalibrate() async {
        recalibrating = true
        defer { recalibrating = false }
        guard await library.connect() else { message = "\(AppBrand.name) can't read your library. Turn on Media & Apple Music for it in the Settings app."; return }
        player.recalibrate()
        message = "Recalibrated: the player is reset and your library was rescanned. Songs in iCloud need an Apple Music subscription to play."
    }

    private func updateCache() { cacheSize = ByteCountFormatter.string(fromByteCount: LivingCoverRenderer.cacheSize, countStyle: .file) }
}

#Preview { SettingsView().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
