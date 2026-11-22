import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Add your own logo to an album, release or artist: pick it from Photos or Files (its background can be taken
/// away), choose its colour, and drag, pinch and twist it into place on the cover. Everything saves as you go.
struct LogoEditorSheet: View {
    let request: LookRequest
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var removeBackground = true
    @State private var working = false
    @State private var failed = false
    @State private var coverColor = Color.white
    /// The position while a gesture is under way (saved when it ends).
    @State private var draft: LogoPlacement?
    @State private var custom = Color.pink
    @State private var canvasSize = CGSize(width: 360, height: 360)

    private var store: LookStore { LookStore.shared }
    private var look: SubjectLook { store.look(request.key) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    canvas
                    if store.logo(request.key) != nil {
                        placementControls
                        tintControls
                    } else {
                        Text("Add a PNG with a see-through background, or any picture: \(AppBrand.name) can take a plain or busy background away.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    sourceControls
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle(request.isArtist ? "Artist Logo" : "Album Logo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .heic, .image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
                if let data { use(data) }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { use(data) }
                    photo = nil
                }
            }
            .task { coverColor = await CoverColor.dominant(request.backdrop) }
            .onAppear { if case .custom(let hex) = look.tint { custom = Color(hex: hex) } }
            .alert("That picture couldn't be used", isPresented: $failed) { Button("OK") {} }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Canvas

    private var canvas: some View {
        let shown = draft ?? look.placement
        return ZStack {
            LookBackdrop(backdrop: request.backdrop)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            if let logo = store.logo(request.key) {
                if let shown {
                    PlacedLogo(image: logo, look: look, placement: shown, coverColor: coverColor)
                } else {
                    TintedLogo(image: logo, tint: look.tint, coverColor: coverColor)
                        .frame(maxWidth: 220, maxHeight: 80, alignment: .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(16)
                        .opacity(0.9)
                }
            }
            if working { ProgressView().controlSize(.large).tint(.white) }
        }
        .aspectRatio(request.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke))
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self, of: \.size) { canvasSize = $0 }
        .gesture(placementGesture, including: look.placement == nil ? .subviews : .all)
        .accessibilityLabel("Logo preview")
        .accessibilityHint(look.placement == nil ? "" : "Drag to move the logo, pinch to resize it, twist to turn it")
    }

    /// Drag to move, pinch to resize and twist to turn, all at once.
    private var placementGesture: some Gesture {
        SimultaneousGesture(DragGesture(minimumDistance: 0), SimultaneousGesture(MagnifyGesture(), RotateGesture()))
            .onChanged { value in
                var p = look.placement ?? LogoPlacement()
                let size = canvasSize
                if let d = value.first, size.width > 0, size.height > 0 {
                    p.x = min(1, max(0, p.x + d.translation.width / size.width))
                    p.y = min(1, max(0, p.y + d.translation.height / size.height))
                }
                if let m = value.second?.first { p.width = min(1.2, max(0.1, p.width * m.magnification)) }
                if let r = value.second?.second { p.rotation += r.rotation.degrees }
                draft = p
            }
            .onEnded { _ in
                guard let final = draft else { return }
                store.update(request.key) { $0.placement = final }
                draft = nil
            }
    }

    // MARK: Controls

    private var placementControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { look.placement != nil }, set: { on in
                store.update(request.key) { $0.placement = on ? LogoPlacement() : nil }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.isArtist ? "Place it on the photo" : "Place it on the cover")
                    Text("Off: the logo sits where the title goes.").font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            if let p = look.placement {
                HStack {
                    Text("Size").font(.subheadline)
                    Slider(value: Binding(get: { p.width }, set: { w in store.update(request.key) { $0.placement?.width = w } }), in: 0.12...1)
                }
                HStack(spacing: 10) {
                    Button("Centre", systemImage: "align.horizontal.center") {
                        store.update(request.key) { $0.placement?.x = 0.5; $0.placement?.rotation = 0 }
                    }
                    Button("Reset", systemImage: "arrow.counterclockwise") { store.update(request.key) { $0.placement = LogoPlacement() } }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var tintControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour").linerLabel(size: 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([LogoTint.original, .mono, .white, .black, .cover], id: \.self) { t in chip(t) }
                    ColorPicker(selection: Binding(get: { custom }, set: { c in
                        custom = c
                        store.update(request.key) { $0.tint = .custom(c.hex) }
                    }), supportsOpacity: false) {
                        Text("Custom").font(.subheadline.weight(.medium))
                    }
                    .fixedSize()
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Capsule().stroke(isCustom ? Color.white : Palette.stroke, lineWidth: isCustom ? 1.5 : 1))
                }
            }
        }
    }

    private var isCustom: Bool { if case .custom = look.tint { true } else { false } }

    private func chip(_ t: LogoTint) -> some View {
        let on = look.tint == t
        return Button { store.update(request.key) { $0.tint = t } } label: {
            HStack(spacing: 6) {
                Circle().fill(swatch(t)).frame(width: 14, height: 14).overlay(Circle().stroke(.white.opacity(0.3)))
                Text(t.label).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(Capsule().stroke(on ? Color.white : Palette.stroke, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func swatch(_ t: LogoTint) -> AnyShapeStyle {
        switch t {
        case .original: AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
        case .mono: AnyShapeStyle(LinearGradient(colors: [.white, .black], startPoint: .leading, endPoint: .trailing))
        case .white: AnyShapeStyle(Color.white)
        case .black: AnyShapeStyle(Color.black)
        case .cover: AnyShapeStyle(coverColor)
        case .custom(let hex): AnyShapeStyle(Color(hex: hex))
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Take the background away", isOn: $removeBackground)
            HStack(spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Photos", systemImage: "photo").frame(maxWidth: .infinity)
                }
                Button { importing = true } label: { Label("Files", systemImage: "folder").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered).controlSize(.large)
            if store.logo(request.key) != nil {
                Button("Remove Logo", systemImage: "trash", role: .destructive) { store.removeLogo(request.key) }
                    .padding(.top, 4)
            }
        }
        .disabled(working)
    }

    private func use(_ data: Data) {
        working = true
        Task {
            let png = await LogoCleaner.prepare(data, removeBackground: removeBackground)
            working = false
            guard let png else { failed = true; return }
            let first = store.logo(request.key) == nil
            store.setLogo(png, for: request.key)
            if first {
                // Your own logo starts on the cover for albums, and white over artist photos.
                store.update(request.key) {
                    $0.placement = LogoPlacement()
                    if request.isArtist { $0.tint = .white }
                }
            }
            // An album without a font of its own takes the one closest to its new logo.
            if !request.isArtist, store.look(request.key).face == nil, let face = await FontMatcher.match(png: png),
               store.look(request.key).face == nil {
                store.update(request.key) { $0.face = face }
            }
        }
    }
}

#Preview {
    LogoEditorSheet(request: .album(.logo, PreviewData.snapshot.albums[0], snapshot: PreviewData.snapshot))
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
