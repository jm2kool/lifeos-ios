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

/// An image that fills whatever space it's given and never grows past it (a bare `scaledToFill` image reports
/// its own oversized width, which pushes whole screens off the edge).
struct FillImage: View {
    let image: UIImage
    var body: some View {
        Color.clear
            .overlay { Image(uiImage: image).resizable().scaledToFill() }
            .clipped()
    }
}
