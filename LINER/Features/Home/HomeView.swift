import SwiftUI

/// Home: the LINER. masthead and Recently Added. (Pinned carousel, mixtapes and mood shelves join in later phases.)
struct HomeView: View {
    @Environment(LibraryService.self) private var library
    @Namespace private var zoom
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppBrand.name).font(.serif(52))
                        Text(AppBrand.tagline).linerLabel()
                    }
                    .padding(.top, 8)

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
            .background(Palette.background)
            .refreshable { await library.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .libraryDestinations(zoom)
        }
    }
}

#Preview { HomeView().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
