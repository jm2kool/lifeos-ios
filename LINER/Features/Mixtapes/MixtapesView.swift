import SwiftData
import SwiftUI

/// Library → Mixtapes: your imported "albums", and the + to import audio files.
struct MixtapesSection: View {
    @Query(sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]
    @State private var importing = false
    @State private var busy = false
    @State private var created: Mixtape?
    let query: String

    private var shown: [Mixtape] {
        query.isEmpty ? mixtapes : mixtapes.filter { $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { importing = true } label: {
                Label(busy ? "Importing…" : "Import audio files", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.linerPrimary).controlSize(.large).disabled(busy)
            .padding(.horizontal, 16)

            if shown.isEmpty {
                EmptyStateView(symbol: "recordingtape", title: query.isEmpty ? "No mixtapes yet" : "No matches",
                               message: "Import mp3, m4a, wav or video files — SoundCloud downloads, voice memos, anything. You can also use “Open in \(AppBrand.name)” from Files or Safari.")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                ForEach(shown) { m in
                    NavigationLink(value: m) { MixtapeTile(mixtape: m) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: MixtapeImporter.allowedTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                busy = true
                let files = await MixtapeImporter.importFiles(urls)
                created = MixtapeImporter.makeMixtape(from: files)
                busy = false
            }
        }
        .navigationDestination(item: $created) { MixtapeEditor(mixtape: $0) }
    }
}

/// A mixtape's cover, from its saved image.
struct MixtapeCover: View {
    let mixtape: Mixtape
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            Palette.placeholder
            if let data = mixtape.coverImage, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "recordingtape").font(.largeTitle).foregroundStyle(Palette.faint)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct MixtapeTile: View {
    let mixtape: Mixtape
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MixtapeCover(mixtape: mixtape)
            Text(mixtape.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Text(mixtape.artist).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Home's Mixtapes shelf.
struct MixtapesShelf: View {
    @Query(filter: #Predicate<Mixtape> { $0.showInHome }, sort: \Mixtape.createdAt, order: .reverse) private var mixtapes: [Mixtape]

    var body: some View {
        if !mixtapes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mixtapes").font(.sectionTitle)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(mixtapes) { m in
                            NavigationLink(value: m) { MixtapeTile(mixtape: m).frame(width: 150) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
