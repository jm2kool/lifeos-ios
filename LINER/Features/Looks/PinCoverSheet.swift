import SwiftData
import SwiftUI

/// Pick which cover a pinned album shows on Home: the album's own (or the cover you set), one of your editions'
/// covers, or the artwork of any edition Apple Music lists.
struct PinCoverSheet: View {
    let request: LookRequest
    @Environment(\.dismiss) private var dismiss
    @Query private var editions: [Edition]
    @State private var catalog: [AppleCatalog.Release] = []

    init(request: LookRequest) {
        self.request = request
        let base = request.key
        _editions = Query(filter: #Predicate<Edition> { $0.baseAlbumID == base }, sort: \Edition.createdAt)
    }

    private var chosen: PinCover { LookStore.shared.look(request.key).pinCover ?? .album }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    option(.album, label: "Album cover") { LookBackdrop(backdrop: request.backdrop) }
                    ForEach(editions.filter { $0.coverImage != nil }) { e in
                        option(.edition(e.id), label: e.title) {
                            if let data = e.coverImage, let img = UIImage(data: data) { FillImage(image: img) } else { Palette.placeholder }
                        }
                    }
                    ForEach(catalog) { r in
                        if let url = r.artwork { option(.remote(url), label: r.title) { RemoteFill(url: url) } }
                    }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("Pin Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { catalog = await AppleCatalog.editions(title: request.title, artist: request.artist) }
        }
    }

    private func option<C: View>(_ cover: PinCover, label: String, @ViewBuilder content: () -> C) -> some View {
        let on = chosen == cover
        return Button {
            LookStore.shared.update(request.key) { $0.pinCover = cover == .album ? nil : cover }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                content()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Color.white : Palette.stroke, lineWidth: on ? 3 : 1))
                    .overlay(alignment: .topTrailing) {
                        if on { Image(systemName: "checkmark.circle.fill").font(.title3).padding(8).symbolRenderingMode(.palette)
                                .foregroundStyle(.black, .white) }
                    }
                Text(label).font(.caption).lineLimit(1).foregroundStyle(on ? Color.white : Palette.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

#Preview {
    PinCoverSheet(request: .album(.pinCover, PreviewData.snapshot.albums[0], snapshot: PreviewData.snapshot))
        .modelContainer(Store.shared.container).environment(PreviewData.library).preferredColorScheme(.dark)
}
