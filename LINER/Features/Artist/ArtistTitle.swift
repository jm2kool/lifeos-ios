import SwiftUI

/// iOS 27-style artist titles: the artist's own logo when there is one, otherwise a lettering style that suits
/// their music. You can pick a different style on the artist page; it's remembered per artist.
enum ArtistTitleStyle: String, CaseIterable, Identifiable {
    case auto, logo, editorial, italic, condensed, wide, quiet, outline, stacked, rounded
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Automatic"
        case .logo: "Artist logo"
        case .editorial: "Editorial serif"
        case .italic: "Serif italic"
        case .condensed: "Heavy condensed"
        case .wide: "Wide mono"
        case .quiet: "Quiet lowercase"
        case .outline: "Outline"
        case .stacked: "Stacked"
        case .rounded: "Rounded"
        }
    }

    /// A lettering style for the artist's genre, varied by name so similar artists don't all look the same.
    static func suggested(name: String, genre: String) -> ArtistTitleStyle {
        let g = genre.lowercased()
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        func pick(_ options: [ArtistTitleStyle]) -> ArtistTitleStyle { options[hash % options.count] }
        if g.contains("hip") || g.contains("rap") || g.contains("trap") { return pick([.condensed, .condensed, .outline]) }
        if g.contains("electr") || g.contains("dance") || g.contains("house") || g.contains("techno") { return pick([.wide, .wide, .rounded]) }
        if g.contains("class") || g.contains("jazz") || g.contains("soundtrack") || g.contains("score") { return pick([.italic, .editorial]) }
        if g.contains("indie") || g.contains("singer") || g.contains("folk") || g.contains("acoustic") || g.contains("lo-fi") { return pick([.quiet, .quiet, .italic]) }
        if g.contains("rock") || g.contains("metal") || g.contains("punk") { return pick([.outline, .condensed]) }
        if g.contains("r&b") || g.contains("soul") { return pick([.italic, .stacked]) }
        if g.contains("bollywood") || g.contains("indian") || g.contains("punjabi") || g.contains("desi") { return pick([.stacked, .italic, .editorial]) }
        if g.contains("pop") || g.contains("k-pop") { return pick([.stacked, .rounded, .editorial]) }
        return pick([.editorial, .stacked, .italic])
    }

    static func saved(for artistID: String) -> ArtistTitleStyle {
        ArtistTitleStyle(rawValue: UserDefaults.standard.string(forKey: "artistTitle.\(artistID)") ?? "") ?? .auto
    }

    static func save(_ style: ArtistTitleStyle, for artistID: String) {
        UserDefaults.standard.set(style == .auto ? nil : style.rawValue, forKey: "artistTitle.\(artistID)")
    }
}

/// The artist's name as a title. `size` is the height of an ordinary title line.
struct ArtistTitleView: View {
    let name: String
    let artistID: String
    let genre: String
    var size: CGFloat = 48
    var style: ArtistTitleStyle
    @State private var logo: UIImage?
    @State private var checked = false

    /// What actually shows: automatic means the logo if we have one, else the suggested lettering.
    private var resolved: ArtistTitleStyle {
        switch style {
        case .auto: logo != nil ? .logo : ArtistTitleStyle.suggested(name: name, genre: genre)
        case .logo: logo != nil ? .logo : ArtistTitleStyle.suggested(name: name, genre: genre)
        default: style
        }
    }

    var body: some View {
        Group {
            if resolved == .logo, let logo {
                Image(uiImage: logo).resizable().scaledToFit()
                    .frame(maxWidth: 300, maxHeight: size * 1.7, alignment: .leading)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                lettering(resolved)
            }
        }
        .animation(.liner, value: logo != nil)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isHeader)
        .task(id: name) {
            if let hit = ArtistLogoStore.shared.cached(name) { logo = hit; return }
            guard style == .auto || style == .logo, !ArtistLogoStore.shared.knownMissing(name) else { return }
            logo = await ArtistLogoStore.shared.logo(for: name)
        }
    }

    @ViewBuilder private func lettering(_ s: ArtistTitleStyle) -> some View {
        switch s {
        case .italic:
            Text(name).font(.system(size: size, weight: .regular, design: .serif)).italic()
                .lineLimit(2).minimumScaleFactor(0.5)
        case .condensed:
            Text(name.uppercased()).font(.system(size: size * 1.05, weight: .black)).fontWidth(.compressed)
                .tracking(-0.5).lineLimit(2).minimumScaleFactor(0.5)
        case .wide:
            Text(name.uppercased()).font(.system(size: size * 0.58, weight: .medium, design: .monospaced)).fontWidth(.expanded)
                .tracking(size * 0.12).lineLimit(2).minimumScaleFactor(0.5)
        case .quiet:
            Text(name.lowercased()).font(.system(size: size * 0.95, weight: .ultraLight)).tracking(1)
                .lineLimit(2).minimumScaleFactor(0.5)
        case .outline:
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) / 8 * 2 * .pi
                    Text(name.uppercased()).font(.system(size: size, weight: .heavy)).fontWidth(.condensed)
                        .foregroundStyle(.white).offset(x: cos(a) * 1.4, y: sin(a) * 1.4)
                }
                Text(name.uppercased()).font(.system(size: size, weight: .heavy)).fontWidth(.condensed).foregroundStyle(.black)
            }
            .compositingGroup().lineLimit(2).minimumScaleFactor(0.5)
        case .stacked:
            VStack(alignment: .leading, spacing: -size * 0.18) {
                ForEach(Array(name.split(separator: " ").enumerated()), id: \.offset) { _, word in
                    Text(String(word)).font(.system(size: size * 1.08, weight: .regular, design: .serif))
                }
            }
            .lineLimit(1).minimumScaleFactor(0.5)
        case .rounded:
            Text(name).font(.system(size: size * 0.95, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.5)
        case .editorial, .auto, .logo:
            Text(name).font(.system(size: size, weight: .regular, design: .serif)).lineLimit(2).minimumScaleFactor(0.55)
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(ArtistTitleStyle.allCases.filter { $0 != .auto && $0 != .logo }) { s in
                ArtistTitleView(name: "Prateek Kuhad", artistID: "p", genre: "Indie", style: s)
            }
        }
        .padding()
    }
    .background(.black).preferredColorScheme(.dark)
}
