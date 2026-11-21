import SwiftUI

/// "Other editions" at the bottom of an album: the deluxe, expanded and other versions Apple Music lists.
/// Tap one to open it.
struct OtherEditionsShelf: View {
    let title: String
    let artist: String
    var excludingID: Int? = nil
    var excludingName: String? = nil
    @State private var editions: [AppleCatalog.Release] = []

    var body: some View {
        Group {
            if !editions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Other Editions").font(.sectionTitle).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(editions) { r in
                                NavigationLink(value: r) { tile(r) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .transition(.opacity)
            }
        }
        .task(id: "\(title)|\(artist)") {
            let found = await AppleCatalog.editions(title: title, artist: artist, excludingID: excludingID, excludingName: excludingName)
            withAnimation(.easeOut(duration: 0.25)) { editions = found }
        }
    }

    private func tile(_ r: AppleCatalog.Release) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CatalogArtwork(url: r.artwork, cornerRadius: 10).frame(width: 150, height: 150)
            Text(r.title).font(.system(size: 14, weight: .medium)).lineLimit(2).frame(width: 150, alignment: .leading)
            Text([r.year.map(String.init), "\(r.trackCount) song\(r.trackCount == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { OtherEditionsShelf(title: "Melodrama", artist: "Lorde") }.preferredColorScheme(.dark)
}
