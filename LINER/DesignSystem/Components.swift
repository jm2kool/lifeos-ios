import SwiftUI

/// Tiny letter-spaced caps label, the house style for section labels.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).linerLabel().frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A dark card: #0E0E0E → #161616, 1px hairline, 22pt continuous corners.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

#Preview {
    Card { SectionLabel("Most played artist"); Text("Lorde").font(.itemTitle) }
        .padding().background(.black)
}
