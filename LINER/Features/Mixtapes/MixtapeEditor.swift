import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Edit a mixtape: details, cover (photo or motion), tracks (rename, reorder, remove) and per-track lyrics.
struct MixtapeEditor: View {
    @Bindable var mixtape: Mixtape
    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var working = false
    @State private var tracks: [MixtapeTrack] = []
    @State private var lyricsFor: MixtapeTrack?

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $mixtape.title)
                TextField("Artist", text: $mixtape.artist)
                TextField("Label", text: Binding(get: { mixtape.label ?? "" }, set: { mixtape.label = $0.nilIfEmpty }))
                TextField("Year", text: Binding(get: { mixtape.year.map(String.init) ?? "" }, set: { mixtape.year = Int($0) }))
                    .keyboardType(.numberPad)
                Toggle("Show on Home", isOn: $mixtape.showInHome)
            }
            Section("Cover") {
                HStack(spacing: 14) {
                    MixtapeCover(mixtape: mixtape, cornerRadius: 10).frame(width: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker("Set cover image", selection: $photo, matching: .images)
                        PhotosPicker("Set motion cover (video)", selection: $video, matching: .videos)
                        if mixtape.motionCoverFile != nil { Button("Remove motion cover", role: .destructive) { mixtape.motionCoverFile = nil } }
                    }
                    .font(.subheadline)
                }
                if working { ProgressView("Preparing motion cover…") }
            }
            Section {
                ForEach(tracks) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Title", text: Binding(get: { t.title }, set: { t.title = $0 }))
                        HStack {
                            TextField("Artist", text: Binding(get: { t.artist }, set: { t.artist = $0 })).font(.caption)
                            Spacer()
                            Button(t.lyricsLRC == nil ? "Add lyrics" : "Lyrics ✓") { lyricsFor = t }.font(.caption).buttonStyle(.borderless)
                        }
                    }
                }
                .onMove { tracks.move(fromOffsets: $0, toOffset: $1); renumber() }
                .onDelete { offsets in
                    for i in offsets {
                        try? FileManager.default.removeItem(at: MixtapeFiles.url(tracks[i].fileName))
                        Store.shared.context.delete(tracks[i])
                    }
                    tracks.remove(atOffsets: offsets)
                    renumber()
                }
            } header: { Text("Tracks") } footer: { Text("Drag to reorder. Swipe to remove a track and its file.") }
        }
        .navigationTitle("Edit Mixtape")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { tracks = mixtape.orderedTracks }
        .onDisappear { Store.shared.save() }
        .onChange(of: photo) { _, p in Task { await loadPhoto(p) } }
        .onChange(of: video) { _, v in Task { await loadVideo(v) } }
        .sheet(item: $lyricsFor) { LRCEditor(track: $0) }
    }

    private func renumber() { for (i, t) in tracks.enumerated() { t.trackNumber = i + 1 } }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        mixtape.coverImage = img.preparingThumbnail(of: CGSize(width: 1400, height: 1400))?.jpegData(compressionQuality: 0.88) ?? data
    }

    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        working = true
        defer { working = false }
        if let name = await MotionCoverImport.importVideo(item, id: "mixtape-\(mixtape.id.uuidString)") {
            mixtape.motionCoverFile = name
            if mixtape.coverImage == nil { mixtape.coverImage = MotionCoverImport.firstFrame(MotionCoverFiles.url(name))?.jpegData(compressionQuality: 0.88) }
        }
    }
}

/// Paste or import an .lrc file for a mixtape track.
struct LRCEditor: View {
    @Bindable var track: MixtapeTrack
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var importing = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $text).font(.system(.footnote, design: .monospaced)).padding()
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text("[00:12.30] Paste synced lyrics here…").font(.footnote).foregroundStyle(.secondary).padding(24).allowsHitTesting(false) }
                }
                .navigationTitle(track.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { track.lyricsLRC = text.nilIfEmpty; Store.shared.save(); dismiss() }
                    }
                    ToolbarItem(placement: .bottomBar) { Button("Import .lrc file", systemImage: "doc") { importing = true } }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]) { r in
                    guard case .success(let url) = r else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    text = (try? String(contentsOf: url, encoding: .utf8)) ?? text
                }
        }
        .onAppear { text = track.lyricsLRC ?? "" }
    }
}
