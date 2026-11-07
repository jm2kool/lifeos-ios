import SwiftUI

/// The OLED-black palette. Colour comes from artwork; everything else is black, white and greys.
enum Palette {
    static let background = Color.black
    static let cardTop = Color(red: 14 / 255, green: 14 / 255, blue: 14 / 255)      // #0E0E0E
    static let cardBottom = Color(red: 22 / 255, green: 22 / 255, blue: 22 / 255)   // #161616
    static let stroke = Color.white.opacity(0.06)
    static let label = Color.white.opacity(0.55)
    static let secondary = Color.white.opacity(0.65)
    static let faint = Color.white.opacity(0.3)
    static let placeholder = Color.white.opacity(0.07)

    static let cardFill = LinearGradient(colors: [cardTop, cardBottom], startPoint: .top, endPoint: .bottom)
    static let cornerRadius: CGFloat = 22
}

extension Animation {
    /// The house spring (response 0.45, damping 0.85).
    static let liner = Animation.spring(response: 0.45, dampingFraction: 0.85)
}
