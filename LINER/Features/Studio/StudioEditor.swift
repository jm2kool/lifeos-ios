import SwiftUI

/// The look being edited, shared by the Studio editor's sections and its live preview.
@MainActor @Observable
final class StudioDraft {
    let album: Album
    var look: StudioLook
    let saved: StudioLook?
    var place: StudioPlace = .album
    /// The album's own artwork, and the colours picked from whichever cover the album page uses.
    var original: UIImage?
    var picked = AlbumColours.black
    var busy = false

    init(album: Album) {
        self.album = album
        saved = StudioStore.shared.look(album.id)
        look = saved ?? StudioLook()
    }

    /// The picture a cover shows (its rendered square, or the album's own artwork).
    func image(_ cover: StudioCover?) -> UIImage? {
        if let name = cover?.rendered, let img = StudioStore.shared.image(name) { return img }
        return original
    }

    var colours: AlbumColours { look.colours(from: picked) }

    /// The page colours as this album will actually show them.
    var shownColours: AlbumColours? { look.shownColours(picked) }

    func refreshColours() async {
        guard let img = image(look.cover(for: .album)) else { return }
        let key = "studio-\(album.id)-\(look.cover(for: .album)?.rendered ?? "original")"
        let found = await AlbumPalette.colours(for: img, key: key)
        withAnimation(.easeInOut(duration: 0.4)) { picked = found }
    }
}

/// LINER. Studio: make every album your own. Up to four covers (choose which one the library grid, the album
/// page, the player and Home's pins use), motion for still covers, the title's lettering, logos, the page's
/// colours and its layout. The preview at the top shows each change straight away.
struct StudioEditor: View {
    @State private var draft: StudioDraft
    @Environment(\.dismiss) private var dismiss

    init(album: Album) { _draft = State(initialValue: StudioDraft(album: album)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StudioPreview(draft: draft)
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Palette.stroke))
                    placePicker
                    StudioCoverSection(draft: draft)
                    StudioMotionSection(draft: draft)
                    StudioTitleSection(draft: draft)
                    StudioColourSection(draft: draft)
                    Button("Reset to the original album", systemImage: "arrow.uturn.backward", role: .destructive) {
                        withAnimation(.liner) { draft.look = StudioLook() }
                        Task { await draft.refreshColours() }
                    }
                    .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LinearGradient(colors: [draft.colours.background.mix(with: .black, by: 0.55), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
                ToolbarItem(placement: .principal) { Text("LINER. STUDIO").font(.system(size: 12, weight: .bold)).tracking(3) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { done() }.fontWeight(.semibold).disabled(draft.busy) }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            var img = CoverOverrides.shared.image(draft.album.id)
            if img == nil { img = await ArtworkCache.shared.image(album: draft.album.id, pixels: 1400) }
            draft.original = img
            await draft.refreshColours()
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    private var placePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Editing", selection: $draft.place) {
                ForEach(StudioPlace.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(draft.place.detail).font(.footnote).foregroundStyle(Palette.label)
        }
    }

    private func cancel() {
        StudioStore.shared.removeUnused(old: draft.look, new: draft.saved)
        dismiss()
    }

    private func done() {
        StudioStore.shared.save(draft.look, for: draft.album.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// A Studio section: a small caps heading over a dark card.
struct StudioCard<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 11, weight: .bold)).tracking(2.2).textCase(.uppercase).foregroundStyle(Palette.label)
                Spacer()
                if let trailing { Text(trailing).font(.caption).foregroundStyle(Palette.faint) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).stroke(Palette.stroke))
    }
}

/// A row of choice chips.
struct StudioChips<ID: Hashable>: View {
    let options: [(id: ID, label: String)]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.id) { option in
                    let on = option.id == selection
                    Button(option.label) {
                        withAnimation(.liner) { selection = option.id }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(on ? Color.black : .white)
                    .background(on ? Color.white : Color.white.opacity(0.08), in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

#Preview {
    StudioEditor(album: PreviewData.snapshot.albums[0])
        .environment(PreviewData.library).environment(PreviewData.player).modelContainer(Store.shared.container)
}
