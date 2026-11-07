import PhotosUI
import SwiftUI

/// Album Passport → Cover: your own still cover or motion cover (video/GIF) for a library album.
struct CoverPickerSection: View {
    @Bindable var note: AlbumNote
    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Cover")
            HStack(spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) { Label("Cover image", systemImage: "photo") }
                PhotosPicker(selection: $video, matching: .any(of: [.videos, .images])) { Label("Motion cover", systemImage: "play.rectangle") }
            }
            .buttonStyle(.glass).font(.footnote)
            if working { ProgressView("Preparing motion cover…").font(.footnote) }
            if note.coverOverride != nil || note.motionCoverFile != nil {
                Button("Use the original artwork", role: .destructive) {
                    if let f = note.motionCoverFile { try? FileManager.default.removeItem(at: MotionCoverFiles.url(f)) }
                    note.coverOverride = nil
                    note.motionCoverFile = nil
                    changed()
                }
                .font(.footnote)
            }
            Text("Motion covers loop behind the player and on the lock screen. Your Apple Music library is never changed.")
                .font(.caption2).foregroundStyle(Palette.label)
        }
        .onChange(of: photo) { _, p in Task { await loadPhoto(p) } }
        .onChange(of: video) { _, v in Task { await loadMotion(v) } }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        note.coverOverride = img.preparingThumbnail(of: CGSize(width: 1400, height: 1400))?.jpegData(compressionQuality: 0.88) ?? data
        changed()
    }

    /// Videos come through as movies; GIFs come through as image data and are converted.
    private func loadMotion(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        working = true
        defer { working = false }
        var name: String?
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            name = await MotionCoverImport.importVideo(item, id: note.albumID)
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            let tmp = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).gif")
            try? data.write(to: tmp)
            name = await MotionCoverImport.importFile(tmp, id: note.albumID)
            try? FileManager.default.removeItem(at: tmp)
        }
        if let name {
            note.motionCoverFile = name
            changed()
        }
    }

    private func changed() {
        Store.shared.save()
        PlaybackCoordinator.shared?.nowPlaying.animated.reset()
    }
}
