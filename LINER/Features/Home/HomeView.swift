import SwiftUI

/// Home: the LINER. masthead, pins, shelves and Recently Added. With Vinyl Mode on, Home is the record crate.
struct HomeView: View {
    @Environment(LibraryService.self) private var library
    @Namespace private var zoom
    @State private var showSettings = false
    @State private var buildingMood = false
    @State private var madeMood: MoodPlaylist?
    @AppStorage("vinylMode") private var vinylMode = false
    /// What's on screen, following `vinylMode` with an animation (the switch can come from anywhere: the
    /// crate's toggle, Settings, the player menu or a double tap on Home).
    @State private var showCrate = UserDefaults.standard.bool(forKey: "vinylMode")

    var body: some View {
        NavigationStack {
            ZStack {
                if showCrate {
                    CrateView(onSettings: { showSettings = true }, onMood: { buildingMood = true }).transition(.crateIn)
                } else {
                    home.transition(.homeOut)
                }
            }
            .onChange(of: vinylMode) { _, on in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { showCrate = on }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: showCrate)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $buildingMood) { MoodBuilderSheet { madeMood = $0 } }
            .navigationDestination(item: $madeMood) { MoodPlaylistDetail(playlist: $0) }
            .libraryDestinations(zoom)
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppBrand.name).font(.serif(52))
                    Text(AppBrand.tagline).linerLabel()
                }
                .padding(.top, 8)

                PinnedGrid()
                HomeShelves()

                Text("Recently Added").font(.sectionTitle)
                if library.recentlyAdded.isEmpty {
                    if library.isLoading { ProgressView().frame(maxWidth: .infinity).padding(40) } else {
                        EmptyStateView(symbol: "square.stack", title: "Your library is empty",
                                       message: "Add albums in the Music app, then pull down here to refresh.")
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                        ForEach(library.recentlyAdded) { album in
                            NavigationLink(value: album) { AlbumTile(album: album, namespace: zoom) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .demoScroll("splash", to: 820, after: 3.4)
        .background(Palette.background)
        .refreshable { await library.refresh() }
        .toolbar {
            // Mood, Vinyl Mode and Settings share one glass capsule.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("New mood playlist", systemImage: "sparkles") { buildingMood = true }
                Button("Vinyl Mode", systemImage: "record.circle") { withAnimation(.liner) { vinylMode = true } }
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
        }
    }
}

extension AnyTransition {
    /// The crate rises up from below like a drawer pulled out, coming into focus.
    static var crateIn: AnyTransition {
        .modifier(active: FocusShift(blur: 14, scale: 1.04, y: 160, opacity: 0), identity: FocusShift(blur: 0, scale: 1, y: 0, opacity: 1))
    }
    /// Home sinks back and softens as the crate comes up (and returns the same way).
    static var homeOut: AnyTransition {
        .modifier(active: FocusShift(blur: 12, scale: 0.92, y: 0, opacity: 0), identity: FocusShift(blur: 0, scale: 1, y: 0, opacity: 1))
    }
}

/// Blur, scale, rise and fade together, for the Home ↔ crate switch.
private struct FocusShift: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let y: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.blur(radius: blur).scaleEffect(scale).offset(y: y).opacity(opacity)
    }
}

#Preview { HomeView().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
