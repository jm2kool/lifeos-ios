import SwiftData
import SwiftUI

/// A mixtape's page, like an album: cover (or motion cover), title, Play/Shuffle, tracks, passport, on a page
/// painted with the cover's colours.
struct MixtapeDetailView: View {
    @Bindable var mixtape: Mixtape
    @Environment(PassportPresenter.self) private var passports
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var adding = false
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var djMix = false
    @State private var colours: [ArtPalette.RGB] = []
    @AppStorage(AlbumText.titleKey) private var titleScale = 1.0

    private var items: [QueueItem] { mixtape.orderedTracks.map { .local(TrackResolver.local($0)) } }

    var body: some View {
        let list = items
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    MixtapeCover(mixtape: mixtape, cornerRadius: 0)
                    if let f = mixtape.motionCoverFile { LoopingVideo(url: MotionCoverFiles.url(f)) }
                }
                .aspectRatio(1, contentMode: .fit).clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 8) {
                    Text(mixtape.title).font(.serif(30 * titleScale)).lineLimit(3)
                    Text(mixtape.artist).linerLabel(size: 12 * titleScale)
                    PlayShuffleItemsRow(items: list) {
                        GlassCircleButton(systemImage: "text.book.closed", label: "Passport", size: 56) { passports.album = .mixtape(mixtape) }
                    }
                    .padding(.top, 10)
                    Text(facts(list)).linerLabel(size: 10).padding(.top, 8)
                }
                .padding(.horizontal, 16).padding(.top, -24)

                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                        PlayableQueueRow(item: item, list: list, number: i + 1).padding(.vertical, 10)
                        Divider().overlay(Palette.stroke)
                    }
                    Button { adding = true } label: { Label(busy ? "Importing…" : "Add tracks", systemImage: "plus") }
                        .buttonStyle(.linerGlass).padding(.top, 16).disabled(busy)
                }
                .padding(.horizontal, 16).padding(.top, 18)
                .albumTextSizes()
            }
            .padding(.bottom, 32)
        }
        .environment(\.mixContext, "mixtape-\(mixtape.id.uuidString)")
        .sheet(isPresented: $djMix) { MixEditorView(context: "mixtape-\(mixtape.id.uuidString)", title: mixtape.title, items: list) }
        .artCanvas(colours)
        .ignoresSafeArea(edges: .top)
        .task(id: mixtape.coverImage?.count ?? 0) {
            guard let data = mixtape.coverImage, let img = UIImage(data: data) else { colours = []; return }
            colours = await ArtPalette.colours(of: [img], key: "mixtape-\(mixtape.id)-\(data.count)")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("DJ Mix", systemImage: "dial.medium") { djMix = true }
                    Toggle("Show on Home", isOn: $mixtape.showInHome)
                    Button("Delete Mixtape", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .navigationDestination(isPresented: $editing) { MixtapeEditor(mixtape: mixtape) }
        .fileImporter(isPresented: $adding, allowedContentTypes: MixtapeImporter.allowedTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                busy = true
                MixtapeImporter.makeMixtape(from: await MixtapeImporter.importFiles(urls), into: mixtape)
                busy = false
            }
        }
        .confirmationDialog("Delete “\(mixtape.title)” and its files?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { MixtapeImporter.delete(mixtape); dismiss() }
        }
    }

    private func facts(_ list: [QueueItem]) -> String {
        var parts = ["MIXTAPE", "\(list.count) TRACK\(list.count == 1 ? "" : "S")", list.reduce(0) { $0 + $1.duration }.minutesLabel]
        if let label = mixtape.label, !label.isEmpty { parts.append(label.uppercased()) }
        if let year = mixtape.year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }
}
