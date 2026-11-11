import SwiftUI

/// The left side of the open sleeve: the cover, full bleed, with the title, the numbers and the credits. The
/// title is left off when the cover already has it printed on it; a logo you added yourself always shows.
/// Sizes follow the panel's width so it reads the same as a full screen or as a landscape square.
struct GatefoldCover: View {
    let record: VinylRecord
    let album: Album?
    let cover: UIImage?
    let tint: Color
    let width: CGFloat
    /// Portrait only: a quiet "Tracks ›" on the right edge.
    var showsHint = true
    /// The album's name is printed on the cover, so it isn't printed again.
    var titleOnCover = false
    /// Your own logo for the album, shown in place of the title.
    var logo: UIImage? = nil
    @Environment(\.gatefoldMetaVisible) private var visible
    @Environment(LibraryService.self) private var library

    var body: some View {
        let u = width / 100
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.07)
            if let cover { FillImage(image: cover) } else { ArtworkView(albumID: record.albumID, cornerRadius: 0) }
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.72), location: 0.64),
                .init(color: .black, location: 0.94),
            ], startPoint: .top, endPoint: .bottom)
            meta(u)
                .padding(.horizontal, 7 * u)
                .padding(.bottom, (showsHint ? 16 : 6) * u)
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(visible ? 0.2 : 0), value: visible)
            if showsHint && visible {
                HStack(spacing: 1.4 * u) {
                    Text("Tracks").linerLabel(size: 2.6 * u).rotationEffect(.degrees(90)).fixedSize()
                    Image(systemName: "chevron.right").font(.system(size: 4 * u, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 4 * u)
                .accessibilityHidden(true)
            }
        }
        .clipped()
    }

    private func meta(_ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker).font(.system(size: 2.6 * u, weight: .semibold)).tracking(0.6 * u).textCase(.uppercase).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let logo {
                Image(uiImage: logo).resizable().scaledToFit()
                    .frame(maxWidth: 70 * u, maxHeight: 24 * u, alignment: .leading)
                    .shadow(color: .black.opacity(0.5), radius: 2 * u)
                    .padding(.top, 3 * u)
                    .accessibilityLabel(record.title)
            } else if !titleOnCover {
                Text(record.title).font(.serif(17 * u)).lineLimit(1).minimumScaleFactor(0.3).padding(.top, 2 * u)
            }
            Text(record.artist).font(.system(size: 3 * u, weight: .semibold)).tracking(0.75 * u).textCase(.uppercase)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 2.4 * u)
            facts(u).padding(.top, 5.5 * u)
            if !writers.isEmpty {
                Text("Written by \(Text(writers).foregroundStyle(Color.white))").foregroundStyle(Palette.label)
                    .font(.system(size: 3.3 * u)).lineLimit(1).minimumScaleFactor(0.55).padding(.top, 4 * u)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func facts(_ u: CGFloat) -> some View {
        let minutes = Int((record.tracks.reduce(0) { $0 + $1.duration } / 60).rounded())
        let editions = album?.editionIDs.count ?? 0
        let third: (String, String) = editions > 1 ? ("\(editions)", "Editions")
            : record.year.map { ("\($0)", "Released") } ?? ("\(record.tracks.count > 1 ? 2 : 1)", record.tracks.count > 1 ? "Sides" : "Side")
        return HStack(spacing: 0) {
            fact("\(record.tracks.count)", record.tracks.count == 1 ? "Song" : "Songs", u)
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
            fact("\(minutes)", "Minutes", u).padding(.leading, 3.6 * u)
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
            fact(third.0, third.1, u).padding(.leading, 3.6 * u)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }

    private func fact(_ value: String, _ label: String, _ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1.4 * u) {
            Text(value).font(.serif(7 * u)).monospacedDigit()
            Text(label).font(.system(size: 2.4 * u, weight: .semibold)).tracking(0.6 * u).textCase(.uppercase).foregroundStyle(Palette.label)
        }
        .padding(.vertical, 3 * u)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kicker: String {
        (["LP"] + [record.year.map(String.init), album?.genre].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: " · ")
    }

    /// The songwriters, from the library (Apple doesn't share producers or labels with apps like this one).
    private var writers: String {
        var seen = Set<String>(), names: [String] = []
        for s in record.tracks.compactMap(\.song) {
            for part in s.composer.split(whereSeparator: { ",&/".contains($0) }) {
                let name = part.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, seen.insert(name.lowercased()).inserted { names.append(name) }
            }
        }
        return names.prefix(4).joined(separator: ", ")
    }
}

/// The right side: the inner sleeve with every song printed like liner notes (Side A and Side B), the record
/// peeking out of the corner, and "Put it on".
struct GatefoldTracks: View {
    let record: VinylRecord
    let cover: UIImage?
    let tint: Color
    let width: CGFloat
    /// Portrait: leaves room at the top for the back button and at the bottom for the page dots.
    var tall = true
    let recordOut: Bool
    let nowPlayingID: String?
    /// Full Album / Saved Album, for albums.
    var tracklist: Choice? = nil
    let onPlay: (Int) -> Void

    struct Choice {
        let savedOnly: Bool
        let fullAvailable: Bool
        let fullCount: Int?
        let savedCount: Int
        let set: (Bool) -> Void
    }

    var body: some View {
        let u = width / 100
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.05)
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 16 * u).frame(maxHeight: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(u)
                    ForEach(sides) { side in sideList(side, u) }
                    Text("\(record.tracks.count) songs, \(Int((record.tracks.reduce(0) { $0 + $1.duration } / 60).rounded())) minutes.")
                        .font(.system(size: 3.2 * u)).foregroundStyle(Palette.faint).padding(.top, 7 * u)
                }
                .padding(.horizontal, 8 * u)
                .padding(.top, (tall ? 30 : 8) * u)
                .padding(.bottom, 48 * u)
            }
            .scrollIndicators(.hidden)
            RecordDisc(record: record, side: "A")
                .frame(width: 84 * u, height: 84 * u)
                .shadow(color: .black.opacity(0.7), radius: 3 * u, x: -2 * u, y: -1 * u)
                .offset(x: recordOut ? 10 * u : 54 * u, y: recordOut ? -70 * u : 30 * u)
                .opacity(recordOut ? 0 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                .frame(height: 22 * u).allowsHitTesting(false)
            Button { onPlay(0) } label: {
                Label("Put it on", systemImage: "play.fill").font(.system(size: 4 * u, weight: .bold))
                    .padding(.horizontal, 2 * u).frame(height: 12 * u)
            }
            .buttonStyle(.linerPrimary).buttonBorderShape(.capsule)
            .padding(.leading, 8 * u).padding(.bottom, (tall ? 16 : 7) * u)
        }
        .clipped()
    }

    private var sides: [RecordSide] { RecordSide.split(record.tracks.count) }

    private func header(_ u: CGFloat) -> some View {
        HStack(spacing: 4 * u) {
            Group { if let cover { FillImage(image: cover) } else { ArtworkView(albumID: record.albumID, cornerRadius: 0) } }
                .frame(width: 15 * u, height: 15 * u).clipShape(RoundedRectangle(cornerRadius: 0.8 * u))
            VStack(alignment: .leading, spacing: 1.6 * u) {
                Text(record.title).font(.serif(7.4 * u)).lineLimit(1).minimumScaleFactor(0.4)
                Text(record.artist).font(.system(size: 2.6 * u, weight: .semibold)).tracking(0.65 * u).textCase(.uppercase)
                    .foregroundStyle(Palette.label).lineLimit(1).minimumScaleFactor(0.6)
                if let t = tracklist { switcher(t, u) }
            }
        }
    }

    private func switcher(_ t: Choice, _ u: CGFloat) -> some View {
        Menu {
            Button { t.set(false) } label: {
                let title = t.fullCount.map { "Full Album · \($0) songs" } ?? "Full Album"
                if !t.savedOnly { Label(title, systemImage: "checkmark") } else { Text(title) }
            }
            .disabled(!t.fullAvailable)
            Button { t.set(true) } label: {
                let title = "Saved Album · \(t.savedCount) song\(t.savedCount == 1 ? "" : "s")"
                if t.savedOnly { Label(title, systemImage: "checkmark") } else { Text(title) }
            }
        } label: {
            HStack(spacing: 0.8 * u) {
                Text(t.savedOnly ? "Saved Album" : "Full Album").font(.system(size: 2.6 * u, weight: .semibold)).tracking(0.65 * u)
                    .textCase(.uppercase).foregroundStyle(tint)
                Image(systemName: "chevron.down").font(.system(size: 2.2 * u, weight: .bold)).foregroundStyle(tint)
            }
        }
        .accessibilityLabel("Tracklist: \(t.savedOnly ? "Saved Album" : "Full Album")")
    }

    private func sideList(_ side: RecordSide, _ u: CGFloat) -> some View {
        let minutes = Int((record.tracks[side.range].reduce(0) { $0 + $1.duration } / 60).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3 * u) {
                Text("Side \(side.name)").font(.system(size: 2.6 * u, weight: .semibold)).tracking(0.65 * u).textCase(.uppercase).foregroundStyle(tint)
                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                Text("\(minutes) min").font(.system(size: 3 * u)).foregroundStyle(Palette.faint).monospacedDigit()
            }
            .padding(.top, 8 * u).padding(.bottom, 1 * u)
            ForEach(side.range, id: \.self) { i in row(i, number: i - side.range.lowerBound + 1, side: side.name, u) }
        }
    }

    private func row(_ i: Int, number: Int, side: String, _ u: CGFloat) -> some View {
        let item = record.tracks[i], playing = item.id == nowPlayingID
        return Button { onPlay(i) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Group {
                    if playing { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(tint) }
                    else { Text("\(side)\(number)").foregroundStyle(Palette.faint) }
                }
                .font(.system(size: 2.8 * u, weight: .semibold)).monospacedDigit()
                .frame(width: 9 * u, alignment: .leading)
                Text(item.title).font(.serif(4.6 * u)).foregroundStyle(playing ? tint : .white).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 3 * u)
                Text(item.duration.trackTime).font(.system(size: 3.2 * u)).foregroundStyle(Palette.label).monospacedDigit()
            }
            .padding(.vertical, 3.1 * u)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.09)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(side)\(number), \(item.title)")
        .accessibilityHint("Puts the record on from this song")
    }
}

#Preview {
    let r = VinylRecord.album(PreviewData.snapshot.albums[0], PreviewData.snapshot)
    HStack(spacing: 12) {
        GatefoldCover(record: r, album: PreviewData.snapshot.albums[0], cover: nil, tint: .orange, width: 300, showsHint: false).frame(width: 300, height: 300)
        GatefoldTracks(record: r, cover: nil, tint: .orange, width: 300, tall: false, recordOut: false, nowPlayingID: nil) { _ in }.frame(width: 300, height: 300)
    }
    .padding().background(.black).environment(PreviewData.library).preferredColorScheme(.dark)
}
