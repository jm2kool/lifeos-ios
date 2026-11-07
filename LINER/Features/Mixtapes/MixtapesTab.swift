import SwiftUI

/// The Mixtapes tab: your imported audio, kept as albums.
struct MixtapesTab: View {
    @Namespace private var zoom
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mixtapes").font(.serif(44))
                        Text("Your own audio, kept like albums").linerLabel()
                    }
                    .padding(.horizontal, 16)
                    MixtapesSection(query: query)
                }
                .padding(.bottom, 24)
            }
            .background(Palette.background)
            .searchable(text: $query, prompt: "Search mixtapes")
            .libraryDestinations(zoom)
        }
    }
}

#Preview { MixtapesTab().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
