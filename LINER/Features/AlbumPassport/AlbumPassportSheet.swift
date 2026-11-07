import SwiftUI

/// Album Passport (SPEC §6.8): rating, your own ranking, editions, listening history, ranking by plays.
struct AlbumPassportSheet: View {
    let subject: AlbumSubject
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryService.self) private var library
    @State private var note: AlbumNote?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let note { content(note) } else { ProgressView().padding(60) }
            }
            .background(Palette.background)
            .navigationTitle("Album Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { AlbumPassportShare.button(subject: subject) }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { note = Store.shared.albumNoteOrNew(subject.id, key: subject.key) }
        .onDisappear { Store.shared.save(); library.reloadPersonalRatings() }
    }

    private func content(_ note: AlbumNote) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                AlbumSubjectArtwork(subject: subject).frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.title).font(.serif(24)).lineLimit(2)
                    Text("\(subject.artist) · \(subject.tracks.count) songs").linerLabel(size: 10)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("My Rating")
                HeartRating(rating: Binding(get: { note.rating }, set: { note.rating = $0 }), size: 28)
            }
            Card {
                NavigationLink { PersonalRankingView(subject: subject, note: note) } label: {
                    row("Personal Album Ranking", "Your order, not your play counts", symbol: "list.number")
                }
                Divider().overlay(Palette.stroke)
                PassportEditionsLink(subject: subject)
            }
            .buttonStyle(.plain)
            if subject.album != nil { CoverPickerSection(note: note) }
            if let album = subject.album { history(album) }
            fullRanking
        }
        .padding(16)
    }

    private func row(_ title: String, _ subtitle: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.faint)
        }
        .contentShape(Rectangle())
    }

    private func history(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("My Listening History")
            HStack(spacing: 10) {
                StatTile("Total plays", value: album.playCount)
                StatTile("Avg plays", text: LibraryStats.averagePlays(album).formatted(.number.precision(.fractionLength(0...1))))
            }
            HStack(spacing: 10) {
                StatTile("Listening", text: "\(library.stats.minutes(of: album).grouped) min", footnote: "Estimated")
                StatTile("Library rank", text: library.stats.rank(of: album).map { "#\($0)" } ?? "—")
            }
        }
    }

    private var fullRanking: some View {
        let songs = subject.tracks.compactMap(\.song).sorted { $0.playCount > $1.playCount }
        return VStack(alignment: .leading, spacing: 8) {
            if !songs.isEmpty {
                SectionLabel("Full Album Ranking · by plays")
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    HStack {
                        Text("\(i + 1)").font(.serif(16)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 26, alignment: .leading)
                        Text(s.title).lineLimit(1)
                        Spacer()
                        Text(s.playCount.grouped).font(.serif(16)).monospacedDigit().foregroundStyle(Palette.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

/// The cover for an album subject (library artwork or the mixtape's cover).
struct AlbumSubjectArtwork: View {
    let subject: AlbumSubject
    var body: some View {
        if let album = subject.album {
            ArtworkView(albumID: album.id, cornerRadius: 12)
        } else if let first = subject.tracks.first {
            QueueItemArtwork(item: first, cornerRadius: 12)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Palette.placeholder)
        }
    }
}

/// Share button for the album passport (share cards arrive with Phase 10).
@MainActor
enum AlbumPassportShare {
    @ViewBuilder static func button(subject: AlbumSubject) -> some View { EmptyView() }
}

/// Personal Editions → Manage.
struct PassportEditionsLink: View {
    let subject: AlbumSubject
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up").frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal Editions").font(.system(size: 16, weight: .medium))
                    Text("Manage your own versions").font(.caption).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.faint)
            }
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $open) { EditionsSheet(subject: subject) }
    }
}

#Preview {
    AlbumPassportSheet(subject: .library(PreviewData.snapshot.albums[0], snapshot: PreviewData.snapshot))
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
