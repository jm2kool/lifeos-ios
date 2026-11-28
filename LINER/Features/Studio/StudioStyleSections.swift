import SwiftUI

/// Motion for still covers, shown on the album page and in the player.
struct StudioMotionSection: View {
    @Bindable var draft: StudioDraft

    var body: some View {
        StudioCard(title: "Motion") {
            Text("Make this cover move gently wherever it shows large.").font(.footnote).foregroundStyle(Palette.label)
            StudioChips(options: StudioMotion.allCases.map { (id: $0, label: $0.label) }, selection: $draft.look.motion)
        }
    }
}

/// The album's title and the top of its page: your logo (placed anywhere on the cover, in any colour), the
/// album's font (including fonts you import), the lettering lifted from the cover, and the cover layout. These
/// open LINER.'s logo and font editors and apply straight away.
struct StudioTitleSection: View {
    @Bindable var draft: StudioDraft
    @Environment(LibraryService.self) private var library
    @AppStorage(AlbumText.plainTitlesKey) private var plainTitles = ""
    @AppStorage("albumLogos") private var albumLogos = true

    private var key: String { LookKey.album(draft.album.id) }

    var body: some View {
        let store = LookStore.shared
        let look = store.look(key)
        StudioCard(title: "Title and logo") {
            HStack(spacing: 10) {
                tile(store.logo(key) == nil ? "Add logo" : "Edit logo", symbol: "signature",
                     detail: look.placement == nil ? "Where the title goes" : "Placed on the cover") {
                    draft.lookRequest = .album(.logo, draft.album, snapshot: library.snapshot)
                }
                tile(look.face == nil ? "Choose font" : look.face?.family ?? "Font", symbol: "textformat",
                     detail: look.face == nil ? "Title, songs, lyrics" : "Size, weight, spacing, capitals") {
                    draft.lookRequest = .album(.font, draft.album, snapshot: library.snapshot)
                }
            }
            Toggle("Lettering from the cover", isOn: lettering).toggleStyle(LinerToggleStyle())
                .font(.system(size: 14, weight: .medium)).disabled(!albumLogos)
            Text("Layout").font(.system(size: 13, weight: .medium)).padding(.top, 4)
            StudioChips(options: [(id: CoverLayout.full, label: "Full screen"), (id: CoverLayout.square, label: "Square")],
                        selection: Binding(get: { look.layout ?? .full }, set: { new in
                            withAnimation(.liner) { store.update(key) { $0.layout = new == .full ? nil : new } }
                        }))
        }
    }

    private func tile(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(Palette.label).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Plain titles are kept as the same comma-separated id list `AlbumTracklist` uses.
    private var lettering: Binding<Bool> {
        let id = "album-\(draft.album.id)"
        return Binding {
            !AlbumTracklist.savedOnly(id, in: plainTitles)
        } set: { on in
            plainTitles = AlbumTracklist.setting(id, savedOnly: !on, in: plainTitles)
        }
    }
}

/// The page's colour and the tracklist's colours: from the cover, or your own.
struct StudioColourSection: View {
    @Bindable var draft: StudioDraft

    var body: some View {
        StudioCard(title: "Colours") {
            swatch("Page", \.background, current: draft.page.first.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) } ?? .black)
            Divider().overlay(Palette.stroke)
            Text("Tracklist").font(.system(size: 13, weight: .medium))
            StudioChips(options: [(id: 0, label: "As in Settings"), (id: 1, label: "Coloured"), (id: 2, label: "White")],
                        selection: Binding(get: { draft.look.colouredTracklist.map { $0 ? 1 : 2 } ?? 0 },
                                           set: { draft.look.colouredTracklist = $0 == 0 ? nil : $0 == 1 }))
            Text("Coloured picks the song names, numbers and the song playing from the cover, like the old Music app.")
                .font(.footnote).foregroundStyle(Palette.label)
            swatch("Song names", \.primary, current: draft.colours.primary)
            swatch("Details", \.secondary, current: draft.colours.secondary)
            swatch("Playing", \.accent, current: draft.colours.accent)
        }
        .onChange(of: draft.look.background) { _, _ in Task { await draft.refreshColours() } }
    }

    private func swatch(_ name: String, _ path: WritableKeyPath<StudioLook, String?>, current: Color) -> some View {
        HStack {
            Text(name).font(.system(size: 13, weight: .medium)).frame(width: 96, alignment: .leading)
            ColorPicker(name, selection: Binding(get: { current }, set: { draft.look[keyPath: path] = $0.hex }), supportsOpacity: false)
                .labelsHidden()
            Spacer()
            if draft.look[keyPath: path] != nil {
                Button("From cover") { draft.look[keyPath: path] = nil }.font(.system(size: 13, weight: .semibold)).buttonStyle(.plain)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}
