import SwiftUI

/// The Library as a crate: records stacked on their spines, only the edge and the name showing.
/// Tap a spine to pull the record up out of the crate; tap it again to open it (albums) or play it (songs).
struct CrateShelf: View {
    enum Entry: Identifiable {
        case album(Album)
        case song(Song, [Song])
        var id: String {
            switch self {
            case .album(let a): "a\(a.id)"
            case .song(let s, _): "s\(s.id)"
            }
        }
        var title: String { switch self { case .album(let a): a.title; case .song(let s, _): s.title } }
        var subtitle: String { switch self { case .album(let a): a.artist; case .song(let s, _): s.artist } }
        var albumID: UInt64 { switch self { case .album(let a): a.id; case .song(let s, _): s.albumID } }
    }

    let entries: [Entry]
    @Environment(PlaybackCoordinator.self) private var player
    @State private var pulled: String?
    @Namespace private var shelf

    var body: some View {
        LazyVStack(spacing: 3) {
            ForEach(entries) { e in
                if pulled == e.id { pulledOut(e) } else { spine(e) }
            }
        }
        .padding(.horizontal, 16)
        .sensoryFeedback(.impact(weight: .medium), trigger: pulled)
    }

    /// A record standing in the crate: a thin strip of its cover, its name along the edge.
    private func spine(_ e: Entry) -> some View {
        Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { pulled = e.id } } label: {
            ZStack(alignment: .leading) {
                ArtworkView(albumID: e.albumID, cornerRadius: 0)
                    .matchedGeometryEffect(id: "art-\(e.id)", in: shelf)
                    .blur(radius: 6).saturation(0.6)
                LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.45), .black.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                // A sliver of the record's edge sticking up out of the sleeve.
                Capsule().fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 6).padding(.vertical, 3).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
                HStack(spacing: 10) {
                    Text(e.title).font(.serif(16)).lineLimit(1)
                    Text(e.subtitle.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.white.opacity(0.07)))
            .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.title), \(e.subtitle)")
        .accessibilityHint("Double-tap to pull it out of the crate")
    }

    /// The pulled-out record: the sleeve with the vinyl sliding out; tap again to open or play.
    @ViewBuilder private func pulledOut(_ e: Entry) -> some View {
        let content = VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(white: 0.05)).padding(10).offset(x: 54)
                    .overlay(RecordDiscLabel(albumID: e.albumID).offset(x: 54))
                ArtworkView(albumID: e.albumID, cornerRadius: 6)
                    .matchedGeometryEffect(id: "art-\(e.id)", in: shelf)
                    .shadow(color: .black.opacity(0.7), radius: 18, y: 10)
            }
            .frame(width: 230, height: 230)
            .padding(.trailing, 54)
            Text(e.title).font(.serif(22)).lineLimit(1)
            Text(e.subtitle).linerLabel(size: 10)
            Text(isAlbum(e) ? "Tap again to open" : "Tap again to play").font(.caption2).foregroundStyle(Palette.label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))

        switch e {
        case .album(let a):
            NavigationLink(value: a) { content }.buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in withAnimation(.liner) { pulled = nil } })
        case .song(let s, let list):
            Button {
                let start = list.firstIndex(of: s) ?? 0
                player.play(songs: Array(list[start..<min(list.count, start + 300)]))
            } label: { content }
            .buttonStyle(.plain)
            .modifier(SongContextMenu(song: s))
        }
    }

    private func isAlbum(_ e: Entry) -> Bool { if case .album = e { true } else { false } }
}

/// The record's centre label (its own artwork) for the pulled-out view.
private struct RecordDiscLabel: View {
    let albumID: UInt64
    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                Circle().stroke(Color.white.opacity(0.04), lineWidth: 0.6).padding(CGFloat(14 + i * 9))
            }
            ArtworkView(albumID: albumID, cornerRadius: 0).frame(width: 74, height: 74).clipShape(Circle())
        }
    }
}
