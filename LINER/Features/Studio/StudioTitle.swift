import CoreText
import SwiftUI

/// Fonts you import into Studio (.ttf / .otf): copied into the Studio folder and registered for LINER. only.
@MainActor
enum StudioFonts {
    private static var registered = false
    private static var folder: URL {
        let url = StudioStore.folder.appending(path: "Fonts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// PostScript names of the fonts you've imported, in the order you added them.
    static var installed: [String] {
        registerAll()
        return UserDefaults.standard.stringArray(forKey: "studioFonts") ?? []
    }

    /// Registers the imported fonts with the system (once per launch).
    static func registerAll() {
        guard !registered else { return }
        registered = true
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }

    /// Imports a font file and returns its PostScript name.
    static func importFont(_ source: URL) -> String? {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let dest = folder.appending(path: source.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(dest as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else {
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
        registerAll()
        CTFontManagerRegisterFontsForURL(dest as CFURL, .process, nil)
        var list = UserDefaults.standard.stringArray(forKey: "studioFonts") ?? []
        if !list.contains(name) { list.append(name) }
        UserDefaults.standard.set(list, forKey: "studioFonts")
        return name
    }

    /// The built-in choices, then your imported ones.
    static var choices: [(id: String, label: String)] {
        [("newYork", "New York"), ("sfPro", "SF Pro"), ("rounded", "Rounded"), ("mono", "SF Mono"), ("compressed", "Compressed")]
            + installed.map { ("custom:\($0)", $0) }
    }

    static func font(_ t: StudioTitle, size: CGFloat? = nil) -> Font {
        let s = size ?? t.size
        let w: Font.Weight = t.bold ? .bold : .regular
        switch t.font {
        case "sfPro": return .system(size: s, weight: w)
        case "rounded": return .system(size: s, weight: w, design: .rounded)
        case "mono": return .system(size: s, weight: w, design: .monospaced)
        case "compressed": return .system(size: s, weight: t.bold ? .black : .semibold).width(.compressed)
        case let f where f.hasPrefix("custom:"):
            registerAll()
            return .custom(String(f.dropFirst(7)), size: s)
        default: return .serif(s, weight: w)
        }
    }
}

/// An album's title as Studio styles it: the lifted cover lettering or text (Auto), your own wording and font
/// (Text), your own logo (Logo), or nothing. Moved by its offset.
struct StudioTitleView: View {
    let albumID: UInt64
    let title: String
    let style: StudioTitle
    let colour: Color
    var alignment: Alignment = .leading

    var body: some View {
        Group {
            switch style.mode {
            case .hidden:
                EmptyView()
            case .logo:
                if let file = style.logoFile, let img = StudioStore.shared.image(file) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxWidth: 260 * style.logoScale, maxHeight: 110 * style.logoScale, alignment: alignment)
                        .shadow(color: .black.opacity(0.35), radius: 8)
                        .accessibilityLabel(title)
                } else {
                    text
                }
            case .auto:
                AlbumTitle(albumID: albumID, title: shown, font: StudioFonts.font(style))
                    .tracking(style.spacing).foregroundStyle(colour)
            case .text:
                text
            }
        }
        .offset(x: style.offsetX, y: style.offsetY)
    }

    private var shown: String {
        let t = style.text?.isEmpty == false ? style.text! : title
        return style.capitals ? t.uppercased() : t
    }

    private var text: some View {
        Text(shown).font(StudioFonts.font(style)).tracking(style.spacing).foregroundStyle(colour)
            .lineLimit(3).minimumScaleFactor(0.5)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
    }
}

/// The artist on an album page: their name, or their logo if you asked Studio for it.
struct StudioArtistLine: View {
    let name: String
    let style: StudioTitle
    let colour: Color
    @State private var logo: UIImage?

    var body: some View {
        Group {
            if style.artistLogo, let logo {
                Image(uiImage: logo).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(colour)
                    .frame(maxWidth: 180 * style.artistLogoScale, maxHeight: 44 * style.artistLogoScale)
                    .accessibilityLabel(name)
            } else {
                Text(name).font(.system(size: 12, weight: .semibold)).textCase(.uppercase).tracking(2.5).foregroundStyle(colour)
            }
        }
        .task(id: "\(name)-\(style.artistLogo)") {
            guard style.artistLogo else { return }
            logo = await ArtistLogoStore.shared.logo(for: name)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        StudioTitleView(albumID: 0, title: "Velvet Hour", style: StudioTitle(mode: .text, font: "compressed", size: 54, capitals: true), colour: .pink)
        StudioArtistLine(name: "Mara Lune", style: StudioTitle(), colour: .white)
    }
    .padding().frame(maxWidth: .infinity).background(Color.indigo)
}
