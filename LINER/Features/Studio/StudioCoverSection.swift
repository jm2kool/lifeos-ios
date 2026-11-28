@preconcurrency import AVFoundation
import PhotosUI
import SwiftUI

/// Studio's covers: up to four per album (the original, photos, videos). Tap one to use it for the place
/// you're editing; hold one to delete it. Photos and the original can be cropped, or extended to fill the
/// square with their own blurred edges.
struct StudioCoverSection: View {
    @Bindable var draft: StudioDraft
    @State private var pickingPhoto = false
    @State private var pickingVideo = false
    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var render: Task<Void, Never>?

    private var selected: StudioCover? { draft.look.cover(for: draft.place) }

    var body: some View {
        StudioCard(title: "Cover", trailing: "\(draft.look.covers.count) of \(StudioLook.maxCovers)") {
            Text("Tap a cover to use it for \(draft.place.label). Hold one to delete it.").font(.footnote).foregroundStyle(Palette.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(draft.look.covers) { thumb($0) }
                    if draft.look.covers.count < StudioLook.maxCovers { addMenu }
                }
                .padding(2)
            }
            if let cover = selected, cover.kind != .video { crop(cover) }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .photosPicker(isPresented: $pickingVideo, selection: $video, matching: .videos)
        .onChange(of: photo) { _, item in if let item { Task { await addPhoto(item) } } }
        .onChange(of: video) { _, item in if let item { Task { await addVideo(item) } } }
    }

    private func thumb(_ cover: StudioCover) -> some View {
        let on = selected?.id == cover.id
        return Button {
            withAnimation(.liner) { draft.look.places[draft.place.rawValue] = cover.id }
            if draft.place == .album { Task { await draft.refreshColours() } }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            ZStack(alignment: .bottom) {
                if let img = draft.image(cover) { FillImage(image: img) } else { Palette.placeholder }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 3) {
                    if cover.kind == .video { Image(systemName: "play.fill") }
                    Text(cover.label)
                }
                .font(.system(size: 9, weight: .bold)).padding(.bottom, 4)
            }
            .frame(width: 66, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Color.white : Palette.stroke, lineWidth: on ? 2.5 : 1))
            .overlay(alignment: .topTrailing) { places(of: cover) }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if draft.look.covers.count > 1 {
                Button("Delete Cover", systemImage: "trash", role: .destructive) { delete(cover) }
            }
        }
        .accessibilityLabel("\(cover.label) cover\(on ? ", in use" : "")")
    }

    /// Little letters showing which places use this cover.
    private func places(of cover: StudioCover) -> some View {
        let letters = StudioPlace.allCases.filter { draft.look.cover(for: $0)?.id == cover.id }.map { String($0.label.prefix(1)) }.joined()
        return Text(letters).font(.system(size: 8, weight: .heavy)).padding(.horizontal, 4).padding(.vertical, 2)
            .background(.black.opacity(0.6), in: Capsule()).padding(3).opacity(letters.isEmpty ? 0 : 1)
    }

    private var addMenu: some View {
        Menu {
            Button("Photo", systemImage: "photo") { pickingPhoto = true }
            Button("Video", systemImage: "play.rectangle") { pickingVideo = true }
            if !draft.look.covers.contains(where: { $0.kind == .original }) {
                Button("Original Artwork", systemImage: "square.stack") { add(StudioCover(kind: .original)) }
            }
        } label: {
            Image(systemName: draft.busy ? "hourglass" : "plus").font(.system(size: 20, weight: .semibold))
                .frame(width: 66, height: 66)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(draft.busy)
        .accessibilityLabel("Add a cover")
    }

    // MARK: Crop

    private func crop(_ cover: StudioCover) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            slider("Zoom", value: cover.zoom, range: cover.extend ? 0.5...1.5 : 1...3) { $0.zoom = $1 }
            slider("Across", value: cover.offsetX, range: -0.5...0.5) { $0.offsetX = $1 }
            slider("Up and down", value: cover.offsetY, range: -0.5...0.5) { $0.offsetY = $1 }
            Toggle("Extend edges", isOn: Binding(get: { cover.extend }, set: { v in change(cover) { $0.extend = v; $0.zoom = 1 } }))
                .font(.system(size: 14, weight: .medium)).toggleStyle(LinerToggleStyle())
            if cover.zoom != 1 || cover.offsetX != 0 || cover.offsetY != 0 || cover.extend {
                Button("Reset Crop", systemImage: "arrow.uturn.backward") { change(cover) { $0.zoom = 1; $0.offsetX = 0; $0.offsetY = 0; $0.extend = false } }
                    .font(.system(size: 13, weight: .semibold)).buttonStyle(.plain).foregroundStyle(Palette.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func slider(_ name: String, value: Double, range: ClosedRange<Double>, set: @escaping (inout StudioCover, Double) -> Void) -> some View {
        HStack {
            Text(name).font(.system(size: 13, weight: .medium)).frame(width: 92, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { v in if let c = selected { change(c) { set(&$0, v) } } }), in: range)
                .tint(.white)
        }
    }

    /// Changes a cover's crop and re-renders its square a moment after you stop moving.
    private func change(_ cover: StudioCover, _ edit: (inout StudioCover) -> Void) {
        guard let k = draft.look.covers.firstIndex(where: { $0.id == cover.id }) else { return }
        edit(&draft.look.covers[k])
        let updated = draft.look.covers[k]
        render?.cancel()
        render = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let source = updated.source.flatMap { StudioStore.shared.image($0) } ?? draft.original
            guard let source, let i = draft.look.covers.firstIndex(where: { $0.id == updated.id }) else { return }
            let plain = !updated.extend && updated.zoom == 1 && updated.offsetX == 0 && updated.offsetY == 0
            let old = draft.look.covers[i].rendered
            if plain && updated.kind == .original {
                draft.look.covers[i].rendered = nil
            } else {
                let square = StudioRender.square(source, zoom: updated.zoom, offsetX: updated.offsetX, offsetY: updated.offsetY, extend: updated.extend)
                draft.look.covers[i].rendered = StudioStore.shared.store(square)
            }
            forget(old)
            if draft.place == .album || draft.look.cover(for: .album)?.id == updated.id { await draft.refreshColours() }
        }
    }

    // MARK: Adding and deleting

    private func add(_ cover: StudioCover) {
        withAnimation(.liner) {
            draft.look.covers.append(cover)
            draft.look.places[draft.place.rawValue] = cover.id
        }
        if draft.place == .album { Task { await draft.refreshColours() } }
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        draft.busy = true
        defer { draft.busy = false; photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        let source = img.preparingThumbnail(of: CGSize(width: 2400, height: 2400 * img.size.height / max(img.size.width, 1))) ?? img
        guard let sourceName = StudioStore.shared.store(source),
              let rendered = StudioStore.shared.store(StudioRender.square(source, zoom: 1, offsetX: 0, offsetY: 0, extend: false)) else { return }
        add(StudioCover(kind: .photo, source: sourceName, rendered: rendered))
    }

    private func addVideo(_ item: PhotosPickerItem) async {
        draft.busy = true
        defer { draft.busy = false; video = nil }
        guard let name = await MotionCoverImport.importVideo(item, id: "studio-\(draft.album.id)") else { return }
        var cover = StudioCover(kind: .video, video: name)
        if let still = await StudioRender.poster(MotionCoverFiles.url(name)) {
            cover.rendered = StudioStore.shared.store(StudioRender.square(still, zoom: 1, offsetX: 0, offsetY: 0, extend: false))
        }
        add(cover)
    }

    private func delete(_ cover: StudioCover) {
        withAnimation(.liner) {
            draft.look.covers.removeAll { $0.id == cover.id }
            draft.look.places = draft.look.places.filter { $0.value != cover.id }
        }
        forget(cover.rendered)
        forget(cover.source)
        if let v = cover.video, draft.saved?.covers.contains(where: { $0.video == v }) != true {
            try? FileManager.default.removeItem(at: MotionCoverFiles.url(v))
        }
        Task { await draft.refreshColours() }
    }

    /// Deletes a picture file unless the saved look still needs it (Cancel goes back to that).
    private func forget(_ name: String?) {
        guard let name, draft.saved?.covers.contains(where: { $0.rendered == name || $0.source == name }) != true else { return }
        try? FileManager.default.removeItem(at: StudioStore.folder.appending(path: name))
    }
}

extension StudioRender {
    /// The first frame of a video cover, for places that show a still.
    static func poster(_ url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        guard let frame = try? await generator.image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: frame)
    }
}
