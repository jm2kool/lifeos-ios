import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A request to add an album's logo, from Photos or from Files (where a transparent PNG usually is).
struct LogoRequest: Identifiable {
    let album: Album
    let fromFiles: Bool
    var id: String { "\(album.id)-\(fromFiles)" }
}

/// "Album Logo" in an album's menu: add your own, change it, or go back to the automatic one.
struct AlbumLogoMenu: View {
    let album: Album
    @Environment(PassportPresenter.self) private var passports

    var body: some View {
        let mine = CustomAlbumLogos.shared.has(album.id)
        Menu("Album Logo", systemImage: "signature") {
            Button(mine ? "Change from Photos" : "Add from Photos", systemImage: "photo") { passports.logo = LogoRequest(album: album, fromFiles: false) }
            Button(mine ? "Change from Files" : "Add from Files", systemImage: "folder") { passports.logo = LogoRequest(album: album, fromFiles: true) }
            if mine {
                Button("Remove My Logo", systemImage: "arrow.uturn.backward", role: .destructive) { CustomAlbumLogos.shared.remove(album.id) }
            }
        }
    }
}

/// Presents the Photos picker or the Files browser for logo requests and saves the result.
struct AlbumLogoPickerHost: ViewModifier {
    @Environment(PassportPresenter.self) private var passports
    @Environment(PlaybackCoordinator.self) private var player
    @State private var picked: PhotosPickerItem?
    /// The request the open picker is for, kept in case the picker closes before it hands its result over.
    @State private var pending: LogoRequest?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: Binding(get: { passports.logo?.fromFiles == false },
                                               set: { if !$0 { close() } }),
                          selection: $picked, matching: .images)
            .onChange(of: picked) { _, item in
                guard let item, let request = passports.logo ?? pending else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    await save(data, for: request.album)
                    picked = nil
                    pending = nil
                    passports.logo = nil
                }
            }
            .fileImporter(isPresented: Binding(get: { passports.logo?.fromFiles == true }, set: { if !$0 { close() } }),
                          allowedContentTypes: [.image]) { result in
                guard let request = passports.logo ?? pending, case .success(let url) = result else { return }
                pending = nil
                let scoped = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
                Task { await save(data, for: request.album) }
            }
    }

    private func close() {
        if let request = passports.logo { pending = request }
        passports.logo = nil
    }

    private func save(_ data: Data?, for album: Album) async {
        var saved = false
        if let data { saved = await CustomAlbumLogos.shared.set(data, for: album.id) }
        player.notice = saved ? "Logo set for “\(album.title)”." : "Couldn't read that picture as a logo."
    }
}

#Preview {
    Menu("Album") { AlbumLogoMenu(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.passports).preferredColorScheme(.dark)
}
