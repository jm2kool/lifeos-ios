import SwiftData
import SwiftUI

/// The glass tab bar (SPEC §8): Home, Library, Mixtapes, My LINER. (with Recaps inside), Search — or the
/// connect screen, which shows on the first launch after every install and after Settings → Recalibrate.
/// The mini player sits in the bottom accessory and zooms open into the full player.
struct RootView: View {
    enum TabID: String { case home, library, mixtapes, recaps, stats, search }

    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.scenePhase) private var phase
    @Environment(PassportPresenter.self) private var passports
    @AppStorage("root.tab") private var tab: TabID = .home
    @Namespace private var playerZoom
    /// Wiped when the app is deleted, so a fresh install always walks through connecting Apple Music again.
    @AppStorage("musicConnected") private var connected = false
    @AppStorage("vinylMode") private var vinylMode = false
    @State private var lastHomeTap = Date.distantPast
    @State private var lastToggle = Date.distantPast

    var body: some View {
        @Bindable var player = player
        @Bindable var passports = passports
        @Bindable var prompts = NewAlbumPrompts.shared
        Group {
            if library.isAuthorized && connected {
                tabs
                    .fullScreenCover(isPresented: $player.showFullPlayer) {
                        FullPlayerView().navigationTransition(.zoom(sourceID: "player", in: playerZoom))
                    }
            } else {
                PermissionView()
            }
        }
        .overlay(alignment: .top) { ErrorBanner() }
        .sheet(item: $passports.song) { SongPassportSheet(item: $0) }
        .sheet(item: $passports.album) { AlbumPassportSheet(subject: $0) }
        .sheet(item: $passports.editions) { EditionsSheet(subject: $0) }
        .modifier(CoverPickerHost())
        .sheet(item: $prompts.current, onDismiss: { NewAlbumPrompts.shared.showNext(library.snapshot) }) { AlbumRatingPrompt(album: $0) }
        .task { if library.isAuthorized && connected && !library.hasLoaded { await library.refresh() } }
        .onOpenURL { url in Task { await openFile(url) } }
        .onChange(of: phase) { _, now in
            if now == .active && library.hasLoaded { library.recheckAccess(); Task { await library.refresh() } }
            if now == .background { SnapshotService.schedule() }
        }
    }

    /// Tab selection that also notices Home being tapped twice quickly (SwiftUI reports a re-tap here on some
    /// iOS versions; the tab bar hook catches it on the rest).
    private var tabSelection: Binding<TabID> {
        Binding(get: { tab }, set: { new in
            if new == .home && tab == .home {
                if Date.now.timeIntervalSince(lastHomeTap) < 0.45 { lastHomeTap = .distantPast; toggleVinyl(); return }
                lastHomeTap = .now
            } else if new == .home {
                lastHomeTap = .now
            }
            tab = new
        })
    }

    /// Double-tap Home: Vinyl Mode on or off (once, however many ways the double tap was noticed).
    private func toggleVinyl() {
        guard Date.now.timeIntervalSince(lastToggle) > 0.6 else { return }
        lastToggle = .now
        tab = .home
        vinylMode.toggle()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// "Open in LINER." from Files, Safari downloads or the share sheet: import into a mixtape.
    private func openFile(_ url: URL) async {
        guard url.isFileURL else { return }
        let files = await MixtapeImporter.importFiles([url])
        try? FileManager.default.removeItem(at: url)   // the system's Inbox copy
        guard let first = files.first else { player.errorMessage = "Couldn't import that file."; return }
        let title = first.album ?? "Inbox"
        let existing = (try? Store.shared.context.fetch(FetchDescriptor<Mixtape>()))?.first { $0.title == title }
        let mixtape = MixtapeImporter.makeMixtape(from: files, into: existing)
        tab = .mixtapes
        player.notice = "Imported “\(first.title)” into \(mixtape?.title ?? title)."
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house", value: TabID.home) { HomeView().onHomeTabDoubleTap { toggleVinyl() } }
            Tab("Library", systemImage: "square.stack", value: TabID.library) { LibraryView() }
            Tab("Mixtapes", systemImage: "recordingtape", value: TabID.mixtapes) { MixtapesTab() }
            Tab("My \(AppBrand.name)", systemImage: "chart.bar.xaxis", value: TabID.stats) { MyStatsView() }
            Tab(value: TabID.search, role: .search) { SearchView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onAppear { if tab == .recaps { tab = .stats } }

        .modifier(MiniPlayerAccessory(enabled: player.current != nil, namespace: playerZoom))
    }
}

/// Shows the mini player only once something has played.
private struct MiniPlayerAccessory: ViewModifier {
    let enabled: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { mini }
        } else {
            content.tabViewBottomAccessory { mini }
        }
    }

    private var mini: some View { MiniPlayer().matchedTransitionSource(id: "player", in: namespace) }
}

/// A dismissible glass banner for playback problems (no subscription, missing file).
private struct ErrorBanner: View {
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        if let message = player.errorMessage ?? player.notice {
            let isError = player.errorMessage != nil
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(isError ? .yellow : .green)
                Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation { player.errorMessage = nil; player.notice = nil } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(for: .seconds(isError ? 8 : 4))
                withAnimation { player.errorMessage = nil; player.notice = nil }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(PreviewData.library)
        .environment(PlaybackCoordinator(library: PreviewData.library))
        .environment(PassportPresenter())
        .modelContainer(Store.shared.container)
        .preferredColorScheme(.dark)
}
