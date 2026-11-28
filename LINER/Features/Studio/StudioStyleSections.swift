import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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

/// The album's title and the artist line: wording, font (including ones you import), size, spacing, capitals,
/// colour, position, your own logo, and the artist's logo.
struct StudioTitleSection: View {
    @Bindable var draft: StudioDraft
    @State private var importingFont = false
    @State private var logoItem: PhotosPickerItem?
    @State private var pickingLogo = false
    @State private var fontError: String?

    private var title: Binding<StudioTitle> { $draft.look.title }

    var body: some View {
        StudioCard(title: "Title") {
            Picker("Title", selection: title.mode) {
                ForEach(StudioTitle.Mode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            switch draft.look.title.mode {
            case .hidden:
                Text("No title on the album page: just the cover.").font(.footnote).foregroundStyle(Palette.label)
            case .logo:
                logoControls
            case .auto, .text:
                textControls
            }
            Divider().overlay(Palette.stroke)
            Toggle("Artist logo instead of name", isOn: title.artistLogo).toggleStyle(LinerToggleStyle()).font(.system(size: 14, weight: .medium))
            if draft.look.title.artistLogo { row("Logo size") { Slider(value: title.artistLogoScale, in: 0.5...2).tint(.white) } }
            if draft.look.title.offsetX != 0 || draft.look.title.offsetY != 0 {
                Button("Put the title back", systemImage: "arrow.uturn.backward") {
                    withAnimation(.liner) { draft.look.title.offsetX = 0; draft.look.title.offsetY = 0 }
                }
                .font(.system(size: 13, weight: .semibold)).buttonStyle(.plain).foregroundStyle(Palette.secondary)
            } else {
                Text("Drag the title on the album preview to move it.").font(.footnote).foregroundStyle(Palette.faint)
            }
        }
        .fileImporter(isPresented: $importingFont, allowedContentTypes: [.font, UTType("public.truetype-ttf-font") ?? .font, UTType("public.opentype-font") ?? .font]) { result in
            guard case .success(let url) = result else { return }
            if let name = StudioFonts.importFont(url) { draft.look.title.font = "custom:\(name)"; draft.look.title.mode = .text }
            else { fontError = "That file isn't a font LINER. can use." }
        }
        .photosPicker(isPresented: $pickingLogo, selection: $logoItem, matching: .images)
        .onChange(of: logoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let name = StudioStore.shared.store(img.preparingThumbnail(of: CGSize(width: 1200, height: 1200 * img.size.height / max(img.size.width, 1))) ?? img, png: true) {
                    draft.look.title.logoFile = name
                }
                logoItem = nil
            }
        }
        .alert("Couldn't add the font", isPresented: Binding(get: { fontError != nil }, set: { if !$0 { fontError = nil } })) {
            Button("OK") {}
        } message: { Text(fontError ?? "") }
    }

    @ViewBuilder private var textControls: some View {
        if draft.look.title.mode == .text {
            TextField(draft.album.title, text: Binding(get: { draft.look.title.text ?? "" }, set: { draft.look.title.text = $0.isEmpty ? nil : $0 }))
                .font(.system(size: 16, weight: .medium)).padding(10)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("Auto uses the lettering lifted from the cover when it's clean, and the font below otherwise.")
                .font(.footnote).foregroundStyle(Palette.label)
        }
        HStack {
            StudioChips(options: StudioFonts.choices, selection: title.font)
            Button { importingFont = true } label: { Image(systemName: "plus").frame(width: 34, height: 34).background(.white.opacity(0.08), in: Circle()) }
                .buttonStyle(.plain).accessibilityLabel("Import a font")
        }
        row("Size") { Slider(value: title.size, in: 20...90).tint(.white) }
        row("Spacing") { Slider(value: title.spacing, in: -2...14).tint(.white) }
        HStack(spacing: 18) {
            Toggle("Bold", isOn: title.bold)
            Toggle("Capitals", isOn: title.capitals)
        }
        .toggleStyle(LinerToggleStyle()).font(.system(size: 14, weight: .medium))
        colourRow
    }

    @ViewBuilder private var logoControls: some View {
        Button(draft.look.title.logoFile == nil ? "Choose a logo (PNG)" : "Change logo", systemImage: "photo.badge.plus") { pickingLogo = true }
            .font(.system(size: 14, weight: .semibold)).buttonStyle(.linerGlass)
        Text("A PNG with a clear background works best.").font(.footnote).foregroundStyle(Palette.label)
        if draft.look.title.logoFile != nil { row("Size") { Slider(value: title.logoScale, in: 0.4...2.2).tint(.white) } }
    }

    private var colourRow: some View {
        HStack {
            Text("Colour").font(.system(size: 13, weight: .medium)).frame(width: 70, alignment: .leading)
            ColorPicker("Title colour", selection: Binding(get: { draft.look.title.colour.flatMap(Color.init(hex:)) ?? draft.colours.primary },
                                                           set: { draft.look.title.colour = $0.hex }), supportsOpacity: false)
                .labelsHidden()
            Spacer()
            if draft.look.title.colour != nil {
                Button("From cover") { draft.look.title.colour = nil }.font(.system(size: 13, weight: .semibold)).buttonStyle(.plain)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    private func row<C: View>(_ name: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(name).font(.system(size: 13, weight: .medium)).frame(width: 70, alignment: .leading); control() }
    }
}

/// The page's colours (from the cover, or your own) and its layout.
struct StudioColourSection: View {
    @Bindable var draft: StudioDraft

    var body: some View {
        StudioCard(title: "Colours and layout") {
            StudioChips(options: [(id: "", label: "As in Settings")] + AlbumPalette.Mode.allCases.map { (id: $0.rawValue, label: $0.label) },
                        selection: Binding(get: { draft.look.colourMode ?? "" }, set: { draft.look.colourMode = $0.isEmpty ? nil : $0 }))
            if draft.shownColours != nil {
                swatch("Background", \.background, draft.colours.background)
                swatch("Titles", \.primary, draft.colours.primary)
                swatch("Details", \.secondary, draft.colours.secondary)
                swatch("Playing", \.accent, draft.colours.accent)
            }
            Divider().overlay(Palette.stroke)
            Text("Layout").font(.system(size: 13, weight: .medium))
            StudioChips(options: StudioLayout.allCases.map { (id: $0, label: $0.label) }, selection: $draft.look.layout)
            Text(layoutNote).font(.footnote).foregroundStyle(Palette.label)
        }
    }

    private var layoutNote: String {
        switch draft.look.layout {
        case .classic: "The cover on top, the title underneath."
        case .poster: "The cover fills the top of the page with the title over it."
        case .centred: "The title, artist and buttons centred under the cover."
        }
    }

    private func swatch(_ name: String, _ path: WritableKeyPath<StudioLook, String?>, _ current: Color) -> some View {
        HStack {
            Text(name).font(.system(size: 13, weight: .medium)).frame(width: 90, alignment: .leading)
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
