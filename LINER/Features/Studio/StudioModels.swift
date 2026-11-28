import SwiftUI

/// Where a Studio cover can show.
enum StudioPlace: String, Codable, CaseIterable, Identifiable, Sendable {
    case grid, album, player, pin
    var id: String { rawValue }
    var label: String { switch self { case .grid: "Grid"; case .album: "Album"; case .player: "Player"; case .pin: "Pin" } }
    var detail: String {
        switch self {
        case .grid: "The square in your library, the crate, search and song rows."
        case .album: "The album page: cover, title, artist, layout and colours."
        case .player: "The full player, the mini player and the Lock Screen."
        case .pin: "The banner when this album is pinned on Home."
        }
    }
}

/// One of up to four covers an album can have.
struct StudioCover: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case original, photo, video }
    var id = UUID()
    var kind: Kind
    /// The photo as picked (Studio folder), so the crop can be changed later.
    var source: String?
    /// The cover as shown: cropped (or extended) to a square, in the Studio folder. Nil means the plain original.
    var rendered: String?
    /// A video cover's file in MotionCoverFiles.
    var video: String?
    /// Crop: 1 shows it all, more zooms in; the offsets move the middle (-0.5…0.5 of the picture).
    var zoom = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    /// Fit the whole picture and fill the edges with it stretched and blurred, instead of cropping.
    var extend = false

    var label: String {
        switch kind { case .original: "Original"; case .photo: "Photo"; case .video: "Video" }
    }
}

/// Moving effects for still covers.
enum StudioMotion: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, zoom, drift, light, focus, particles, film
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"; case .zoom: "Zoom"; case .drift: "Drift"; case .light: "Light"
        case .focus: "Focus"; case .particles: "Particles"; case .film: "Film"
        }
    }
    var symbol: String {
        switch self {
        case .off: "circle.slash"; case .zoom: "plus.magnifyingglass"; case .drift: "arrow.up.and.down.and.arrow.left.and.right"
        case .light: "sun.max"; case .focus: "camera.aperture"; case .particles: "sparkles"; case .film: "film"
        }
    }
}

/// Everything Studio changes about one album.
struct StudioLook: Codable, Hashable, Sendable {
    var covers: [StudioCover] = [StudioCover(kind: .original)]
    /// Which cover each place uses (by cover id); places left out use the first cover.
    var places: [String: UUID] = [:]
    var motion: StudioMotion = .off
    /// Colour the tracklist from the cover; nil follows Settings → Covers → Coloured tracklists.
    var colouredTracklist: Bool?
    /// Hex overrides: the page's colour below the cover, song names, details, and the song playing.
    var background: String?
    var primary: String?
    var secondary: String?
    var accent: String?

    static let maxCovers = 4

    /// Nothing changed from the album as it comes.
    var isPlain: Bool {
        covers.count == 1 && covers[0].kind == .original && covers[0].rendered == nil && places.isEmpty && motion == .off
            && colouredTracklist == nil && background == nil && primary == nil && secondary == nil && accent == nil
    }

    func cover(for place: StudioPlace) -> StudioCover? {
        if let id = places[place.rawValue], let c = covers.first(where: { $0.id == id }) { return c }
        return covers.first
    }

    /// The tracklist colours an album page shows (nil for LINER.'s plain white text).
    func shownColours(_ picked: AlbumColours) -> AlbumColours? {
        guard colouredTracklist ?? AlbumPalette.enabled else {
            // Colours you set yourself still show with coloured tracklists off.
            return primary == nil && secondary == nil && accent == nil ? nil : colours(from: .black)
        }
        return colours(from: picked)
    }

    /// The colours with your overrides on top of the ones taken from the cover.
    func colours(from picked: AlbumColours) -> AlbumColours {
        var c = picked
        if let h = background { c.background = Color(hex: h); c.isDark = UIColor(Color(hex: h)).luminance < 0.4 }
        if let h = primary { c.primary = Color(hex: h) }
        if let h = secondary { c.secondary = Color(hex: h) }
        if let h = accent { c.accent = Color(hex: h) }
        return c
    }
}

extension UIColor {
    /// Relative luminance, 0 (black) to 1 (white).
    var luminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func ch(_ c: CGFloat) -> Double { let c = Double(c); return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    }
}
