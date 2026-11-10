import SwiftUI

/// Group versions of an album the app didn't group by itself (a live album, a re-release under another name):
/// tick the other albums and they become one album, led by the one with the most songs, like grouped editions.
/// An album that's already several editions can be separated again here.
struct GroupAlbumsSheet: View {
    let album: Album
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Set<UInt64>()
    @State private var search = ""

    /// This album's own IDs: every edition already in it.
    private var ownIDs: [UInt64] { album.editionIDs.isEmpty ? [album.id] : album.editionIDs }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ArtworkView(albumID: album.id, cornerRadius: 6).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.title).font(.serif(20)).lineLimit(2)
                            Text(album.artist).linerLabel(size: 10)
                            if album.editionIDs.count > 1 {
                                Text("\(album.editionIDs.count) versions grouped").font(.caption).foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                    if album.editionIDs.count > 1 {
                        Button("Separate the Versions Again", systemImage: "rectangle.split.3x1", role: .destructive) { separate() }
                    }
                } footer: {
                    Text("Grouped albums show as one, led by the version with the most songs; songs only on the others are added after its tracklist.")
                }
                Section(search.isEmpty ? "By \(album.artist)" : "Albums") {
                    if candidates.isEmpty { Text("No other albums found.").foregroundStyle(Palette.secondary) }
                    ForEach(candidates) { a in row(a) }
                }
            }
            .searchable(text: $search, prompt: "Find another album")
            .navigationTitle("Group Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Group", systemImage: "checkmark") { group() }.disabled(chosen.isEmpty)
                }
            }
        }
    }

    /// The artist's other albums, or any album matching the search.
    private var candidates: [Album] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let others = library.albums(.alphabetical).filter { $0.id != album.id }
        if q.isEmpty { return others.filter { MediaKey.normalise($0.artist) == MediaKey.normalise(album.artist) } }
        return others.filter { $0.title.localizedStandardContains(q) || $0.artist.localizedStandardContains(q) }
    }

    private func row(_ a: Album) -> some View {
        let on = chosen.contains(a.id)
        return Button {
            if on { chosen.remove(a.id) } else { chosen.insert(a.id) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                ArtworkView(albumID: a.id, cornerRadius: 4).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Text([a.artist, a.year.map(String.init), "\(a.songCount) songs"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? .white : Palette.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func group() {
        let picked = library.albums(.alphabetical).filter { chosen.contains($0.id) }
        AlbumGroups.group(ownIDs + picked.flatMap { $0.editionIDs.isEmpty ? [$0.id] : $0.editionIDs })
        player.notice = "Grouped \(picked.count + 1) albums into “\(album.title)”."
        refresh()
    }

    private func separate() {
        AlbumGroups.ungroup(album.editionIDs)
        player.notice = "Separated the versions of “\(album.title)”."
        refresh()
    }

    private func refresh() {
        dismiss()
        Task { await library.refresh() }
    }
}

#Preview {
    GroupAlbumsSheet(album: PreviewData.snapshot.albums[0])
        .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
