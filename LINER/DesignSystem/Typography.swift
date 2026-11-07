import SwiftUI

/// Editorial serif (New York) for titles and numbers; tiny letter-spaced caps for labels.
extension Font {
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Artist names.
    static let artistTitle = serif(48)
    /// Album and song titles.
    static let itemTitle = serif(30)
    /// Section titles such as "My Top Songs".
    static let sectionTitle = serif(26)
    /// Big numbers in stat tiles.
    static let statNumber = serif(32)
}

extension View {
    /// Uppercase, 2.5pt tracking, 55% white: `MOST PLAYED ARTIST`.
    func linerLabel(size: CGFloat = 11) -> some View {
        self.font(.system(size: size, weight: .semibold))
            .textCase(.uppercase)
            .tracking(2.5)
            .foregroundStyle(Palette.label)
    }
}

extension Int {
    /// Grouped digits in the user's locale (11,557 in India).
    var grouped: String { formatted(.number) }
}
