import SwiftUI
import UniformTypeIdentifiers

/// Pick a font for one album: every family on the iPhone and any you import, previewed with the album's own title
/// and songs. It's used for the title, the tracklist and the sleeve (and the player, if you switch that on).
struct FontPickerSheet: View {
    let request: LookRequest
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var importing = false
    @State private var imported: [String] = []
    @State private var system: [String] = []
    @State private var importFailed = false

    private var store: LookStore { LookStore.shared }
    private var face: AlbumFace? { store.look(request.key).face }

    var body: some View {
        NavigationStack {
            List {
                Section { preview }
                if let face { Section("Style") { styleControls(face) } }
                Section {
                    row(nil, name: "\(AppBrand.name) default")
                    ForEach(filtered(AlbumFace.systemFamilies), id: \.self) { row($0, name: $0) }
                } header: { Text("System") }
                if !imported.isEmpty {
                    Section("Your fonts") { ForEach(filtered(imported), id: \.self) { row($0, name: $0) } }
                }
                Section {
                    Button("Import a Font (.ttf, .otf)", systemImage: "square.and.arrow.down") { importing = true }
                } footer: {
                    Text("Fonts you import stay in \(AppBrand.name). and are included in backups.")
                }
                Section("On this iPhone") { ForEach(filtered(system), id: \.self) { row($0, name: $0) } }
            }
            .searchable(text: $search, prompt: "Fonts")
            .navigationTitle("Album Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.font, UTType(filenameExtension: "ttf") ?? .font,
                                                                           UTType(filenameExtension: "otf") ?? .font]) { result in
                guard case .success(let url) = result else { return }
                if let family = FontLibrary.importFont(from: url) {
                    imported = FontLibrary.importedFamilies()
                    pick(family)
                } else {
                    importFailed = true
                }
            }
            .alert("That file isn't a font LINER. can read", isPresented: $importFailed) { Button("OK") {} }
            .onAppear {
                FontLibrary.registerImported()
                imported = FontLibrary.importedFamilies()
                system = FontLibrary.systemFamilies().filter { !AlbumFace.systemFamilies.contains($0) }
            }
        }
    }

    private func filtered(_ list: [String]) -> [String] {
        search.isEmpty ? list : list.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.title).albumFace(32, fallback: .itemTitle).lineLimit(2).minimumScaleFactor(0.5)
            ForEach(Array(request.songs.prefix(3).enumerated()), id: \.offset) { i, title in
                HStack(spacing: 12) {
                    Text("\(i + 1)").albumFace(17, fallback: .serif(17)).foregroundStyle(Palette.label).monospacedDigit().frame(width: 22)
                    Text(title).albumFace(16, fallback: .system(size: 16)).lineLimit(1)
                }
            }
        }
        .environment(\.albumFace, face)
        .padding(.vertical, 6)
        .animation(.easeOut(duration: 0.2), value: face)
    }

    private func row(_ family: String?, name: String) -> some View {
        let on = face?.family == family
        return Button {
            if let family { pick(family) } else { clear() }
        } label: {
            HStack {
                Text(name)
                    .font(family.map { AlbumFace(family: $0).font(19) } ?? .serif(19))
                    .lineLimit(1)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func styleControls(_ face: AlbumFace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weight · \(AlbumFace.weightNames[face.weight])").font(.subheadline)
            Slider(value: Binding(get: { Double(face.weight) }, set: { v in change { $0.weight = Int(v.rounded()) } }), in: 0...8, step: 1)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Letter spacing").font(.subheadline)
            Slider(value: Binding(get: { face.tracking }, set: { v in change { $0.tracking = v } }), in: -2...8)
        }
        Picker("Capitals", selection: Binding(get: { face.caps }, set: { c in change { $0.caps = c } })) {
            Text("As written").tag(AlbumFace.Caps.normal)
            Text("ALL CAPS").tag(AlbumFace.Caps.upper)
            Text("lowercase").tag(AlbumFace.Caps.lower)
        }
        Toggle("Use in the player too", isOn: Binding(get: { face.inPlayer }, set: { v in change { $0.inPlayer = v } }))
    }

    private func pick(_ family: String) {
        store.update(request.key) { l in
            var f = l.face ?? AlbumFace(family: family)
            f.family = family
            l.face = f
        }
    }

    private func clear() { store.update(request.key) { $0.face = nil } }

    private func change(_ edit: (inout AlbumFace) -> Void) {
        store.update(request.key) { l in
            guard var f = l.face else { return }
            edit(&f)
            l.face = f
        }
    }
}

#Preview {
    FontPickerSheet(request: .album(.font, PreviewData.snapshot.albums[0], snapshot: PreviewData.snapshot)).preferredColorScheme(.dark)
}
