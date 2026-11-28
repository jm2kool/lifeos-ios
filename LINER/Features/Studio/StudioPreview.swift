import SwiftUI

/// The live preview at the top of Studio: the place being edited (library grid, album page, player or pin),
/// drawn with the draft look and the album's logo, font and layout.
struct StudioPreview: View {
    let draft: StudioDraft
    @Environment(LibraryService.self) private var library

    var body: some View {
        ZStack {
            switch draft.place {
            case .album: albumPage
            case .grid: grid
            case .player: playerScreen
            case .pin: pin
            }
        }
        .animation(.liner, value: draft.place)
    }

    private var lookKey: String { LookKey.album(draft.album.id) }

    // MARK: Album page

    private var albumPage: some View {
        let look = LookStore.shared.look(lookKey)
        let tint = draft.shownColours
        return ZStack(alignment: .top) {
            ArtCanvas(colours: draft.page)
            if look.layout == .square {
                StudioCoverDisplay(draft: draft, place: .album)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                    .padding(.top, 22)
            } else {
                StudioCoverDisplay(draft: draft, place: .album).frame(height: 230).clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                AlbumLogoTitle(lookKey: lookKey, albumID: draft.album.id, title: draft.album.title, maxWidth: 220, maxHeight: 70,
                               font: .serif(26), fontSize: 26)
                Text(draft.album.artist).linerLabel(size: 10)
                HStack(spacing: 8) {
                    Label("Play", systemImage: "play.fill").font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background((tint?.accent.mix(with: .white, by: 0.25) ?? .white), in: Capsule()).foregroundStyle(.black)
                    Image(systemName: "shuffle").font(.system(size: 12, weight: .bold)).frame(width: 32, height: 32)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(Array(trackNames.enumerated()), id: \.offset) { i, name in
                        HStack(spacing: 10) {
                            if i == 1 { PlayingBars(colour: tint?.accent ?? .white, playing: true).frame(width: 18) }
                            else { Text("\(i + 1)").font(.serif(13)).foregroundStyle(tint?.secondary ?? Palette.label).frame(width: 18) }
                            Text(name).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(i == 1 ? (tint?.accent ?? .white) : (tint?.primary ?? .white)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { Rectangle().fill((tint?.primary ?? .white).opacity(0.14)).frame(height: 0.5) }
                    }
                }
                .padding(.top, 6)
            }
            .environment(\.albumFace, look.face)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var trackNames: [String] {
        let names = library.snapshot.songs(draft.album.songIDs).prefix(3).map(\.title)
        return names.isEmpty ? ["Opening", "The single", "Closer"] : Array(names)
    }

    // MARK: Other places

    private var grid: some View {
        ZStack {
            Color.black
            LazyVGrid(columns: [GridItem(.fixed(130), spacing: 14), GridItem(.fixed(130), spacing: 14)], spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    StudioCoverDisplay(draft: draft, place: .grid).frame(width: 130, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(draft.album.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(draft.album.artist).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.placeholder).frame(width: 130, height: 130)
                        Capsule().fill(Palette.placeholder).frame(width: 80, height: 8)
                    }
                }
            }
        }
    }

    private var playerScreen: some View {
        ZStack(alignment: .bottomLeading) {
            StudioCoverDisplay(draft: draft, place: .player)
            LinearGradient(colors: [.clear, .black.opacity(0.75), .black], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(trackNames.first ?? draft.album.title).font(.serif(24)).lineLimit(1)
                Text(draft.album.artist).font(.system(size: 10, weight: .semibold)).tracking(2.5).textCase(.uppercase).foregroundStyle(.white.opacity(0.7))
                Capsule().fill(.white.opacity(0.25)).frame(height: 4).overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 90, height: 4) }
                HStack(spacing: 40) { Image(systemName: "backward.fill"); Image(systemName: "pause.fill"); Image(systemName: "forward.fill") }
                    .font(.system(size: 22)).frame(maxWidth: .infinity)
            }
            .padding(18)
        }
    }

    private var pin: some View {
        ZStack {
            Color.black
            ZStack(alignment: .bottomLeading) {
                StudioCoverDisplay(draft: draft, place: .pin)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.album.title).font(.serif(26)).lineLimit(1)
                    Text(draft.album.artist).font(.system(size: 10, weight: .semibold)).tracking(2.5).textCase(.uppercase).foregroundStyle(Palette.label)
                }
                .padding(16)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
            .padding(16)
        }
    }
}

/// The cover a place shows in the draft: its video, or its picture with the motion effect.
struct StudioCoverDisplay: View {
    let draft: StudioDraft
    let place: StudioPlace

    var body: some View {
        let cover = draft.look.cover(for: place)
        Group {
            if cover?.kind == .video, let name = cover?.video {
                LoopingVideo(url: MotionCoverFiles.url(name))
            } else if let img = draft.image(cover) {
                StudioMotionView(image: img, motion: place == .grid ? .off : draft.look.motion, key: cover?.rendered ?? "orig-\(draft.album.id)")
            } else {
                Palette.placeholder
            }
        }
        .id("\(cover?.id.uuidString ?? "")-\(cover?.rendered ?? "")-\(draft.look.motion.rawValue)")
    }
}
