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
            .buttonStyle(.linerGlass).font(.footnote)
            if working { ProgressView("Preparing motion cover…").font(.footnote) }
            if note.coverOverride != nil || note.motionCoverFile != nil {
                Button("Use the original artwork", role: .destructive) { if let album { CoverSaver.reset(album) } }
                .font(.footnote)
            }
            Text("Motion covers loop behind the player and on the lock screen. Your Apple Music library is never changed.")
                .font(.caption2).foregroundStyle(Palette.label)
        }
        .onChange(of: photo) { _, p in Task { await loadPhoto(p) } }
        .onChange(of: video) { _, v in Task { await loadMotion(v) } }
    }

    private var album: Album? {
        guard note.albumID.hasPrefix("album-"), let id = UInt64(note.albumID.dropFirst(6)) else { return nil }
        return LibraryService.current?.snapshot.album(id)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let album else { return }
        await CoverSaver.save(item, for: CoverRequest(album: album, motion: false))
    }

    /// Videos come through as movies; GIFs come through as image data and are converted.
    private func loadMotion(_ item: PhotosPickerItem?) async {
        guard let item, let album else { return }
        working = true
        defer { working = false }
        await CoverSaver.save(item, for: CoverRequest(album: album, motion: true))
    }
}
