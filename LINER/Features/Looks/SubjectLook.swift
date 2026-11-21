import SwiftUI

/// The colour a logo you add is shown in.
enum LogoTint: Codable, Hashable, Sendable {
    /// As the image is.
    case original
    /// Black and white.
    case mono
    case white
    case black
    /// The cover's main colour.
    case cover
    /// Any colour from the colour wheel, as hex.
    case custom(String)

    var label: String {
        switch self {
        case .original: "Original"
        case .mono: "B&W"
        case .white: "White"
        case .black: "Black"
        case .cover: "Cover"
        case .custom: "Custom"
        }
    }
}

/// Where a logo sits on the album cover or artist photo, in unit coordinates of that header.
struct LogoPlacement: Codable, Hashable, Sendable {
    /// The logo's centre.
    var x = 0.5
    var y = 0.78
    /// Its width as a fraction of the header's width.
    var width = 0.62
    var rotation = 0.0
}

/// How an album page shows its cover: edge to edge, or as a square card.
enum CoverLayout: String, Codable, Hashable, Sendable {
    case full, square
}

/// Which picture a pinned album shows on Home.
enum PinCover: Codable, Hashable, Sendable {
    case album
    case edition(UUID)
    case remote(URL)
}

/// A font you picked for an album: its title, tracklist and sleeve (and, if you like, the player).
struct AlbumFace: Codable, Hashable, Sendable {
    enum Caps: String, Codable, CaseIterable, Sendable { case normal, upper, lower }

    /// A font family, or one of the system designs below.
    var family: String
    /// 0 (ultralight) … 8 (black).
    var weight = 3
    var tracking = 0.0
    var caps = Caps.normal
    var inPlayer = false

    static let systemSans = "System"
    static let systemSerif = "New York"
    static let systemRounded = "SF Rounded"
    static let systemMono = "SF Mono"
    static let systemFamilies = [systemSans, systemSerif, systemRounded, systemMono]

    static var weights: [Font.Weight] { [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black] }
    static let weightNames = ["Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]

    var fontWeight: Font.Weight { Self.weights[max(0, min(Self.weights.count - 1, weight))] }

    func font(_ size: CGFloat) -> Font {
        switch family {
        case Self.systemSans: .system(size: size, weight: fontWeight)
        case Self.systemSerif: .system(size: size, weight: fontWeight, design: .serif)
        case Self.systemRounded: .system(size: size, weight: fontWeight, design: .rounded)
        case Self.systemMono: .system(size: size, weight: fontWeight, design: .monospaced)
        default: .custom(family, size: size).weight(fontWeight)
        }
    }

    var textCase: Text.Case? {
        switch caps {
        case .normal: nil
        case .upper: .uppercase
        case .lower: .lowercase
        }
    }
}

/// Everything you've changed about how one album, release or artist looks.
struct SubjectLook: Codable, Hashable, Sendable {
    /// File name of your logo in Application Support/LINER/Logos.
    var logoFile: String?
    var tint = LogoTint.original
    /// nil keeps the logo where the title goes.
    var placement: LogoPlacement?
    var layout: CoverLayout?
    var face: AlbumFace?
    var pinCover: PinCover?

    var isEmpty: Bool { self == SubjectLook() }
}

/// What a look belongs to. The key is stable across launches and goes into backups.
enum LookKey {
    static func album(_ id: UInt64) -> String { "album-\(id)" }
    static func release(_ id: Int) -> String { "release-\(id)" }
    static func artist(_ name: String) -> String { "artist-\(MediaKey.normalise(name))" }
}

extension EnvironmentValues {
    /// The font chosen for the album on screen (nil keeps LINER.'s own).
    @Entry var albumFace: AlbumFace? = nil
}

/// Text in the album's own font when it has one.
struct FaceModifier: ViewModifier {
    let size: CGFloat
    let fallback: Font
    @Environment(\.albumFace) private var face

    func body(content: Content) -> some View {
        if let face {
            content.font(face.font(size)).tracking(face.tracking).textCase(face.textCase)
        } else {
            content.font(fallback)
        }
    }
}

extension View {
    /// Uses the album's font (from `albumFace`) at this size, or `fallback` when it has none.
    func albumFace(_ size: CGFloat, fallback: Font) -> some View { modifier(FaceModifier(size: size, fallback: fallback)) }
}

extension Color {
    /// A colour saved as "#RRGGBB" (see `hex`).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt32(s, radix: 16) ?? 0xFFFFFF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
