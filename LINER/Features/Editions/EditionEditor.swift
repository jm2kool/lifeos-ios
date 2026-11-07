import PhotosUI
import SwiftUI

/// Edit an edition: name, cover (photo or motion), and the tracklist (add from library or mixtapes, remove, reorder).
struct EditionEditor: View {
    @Bindable var edition: Edition
    @Environment(LibraryService.self) private var library
    @State private var items: [QueueItem] = []
    @State private var adding = false
    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var working = false

    var body: some View {
        List {
            Section("Name") {
                TextField("Edition name", text: $edition.title).font(.serif(20))
            }
            Section("Cover") {
                HStack(spacing: 14) {
                    coverPreview.frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker("Set cover image", selection: $photo, matching: .images)
                        PhotosPicker("Set motion cover (video)", selection: $video, matching: .videos)
                        if edition.coverImage != nil || edition.motionCoverFile != nil {
                            Button("Remove cover", role: .destructive) { edition.coverImage = nil; edition.motionCoverFile = nil }
                        }
                    }
                    .font(.subheadline)
                }
                if working { ProgressView("Preparing motion cover…") }
            }
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.serif(16)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 26)
                        QueueItemArtwork(item: item).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).lineLimit(1)
                            Text(item.artist).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                        }
                        if !item.isLibrary { Spacer(); Image(systemName: "recordingtape").font(.caption).foregroundStyle(Palette.faint) }
                    }
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1); save() }
                .onDelete { items.remove(atOffsets: $0); save() }
                Button("+ Add Songs", systemImage: "plus") { adding = true }
            } header: {
                Text("Tracklist")
            } footer: {
                Text("Your Apple Music library is never modified.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit Edition")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { items = TrackResolver.items(edition.tracks, snapshot: library.snapshot) }
        .sheet(isPresented: $adding) { AddSongsSheet { new in items.append(contentsOf: new); save() } }
        .onChange(of: photo) { _, p in Task { await loadPhoto(p) } }
        .onChange(of: video) { _, v in Task { await loadVideo(v) } }
        .onDisappear { Store.shared.save() }
    }

    @ViewBuilder private var coverPreview: some View {
        if let data = edition.coverImage, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let first = items.first {
            QueueItemArtwork(item: first, cornerRadius: 10)
        } else {
            RoundedRectangle(cornerRadius: 10).fill(Palette.placeholder)
        }
    }

    private func save() { edition.tracks = items.map(TrackResolver.reference) }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        edition.coverImage = img.preparingThumbnail(of: CGSize(width: 1400, height: 1400))?.jpegData(compressionQuality: 0.88) ?? data
    }

    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        working = true
        defer { working = false }
        if let name = await MotionCoverImport.importVideo(item, id: "edition-\(edition.id.uuidString)") {
            edition.motionCoverFile = name
            if edition.coverImage == nil, let still = MotionCoverImport.firstFrame(MotionCoverFiles.url(name)) {
                edition.coverImage = still.jpegData(compressionQuality: 0.88)
            }
        }
    }
}
