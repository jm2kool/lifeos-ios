import SwiftUI

/// A stat tile: small caps label over a big serif number (`TOTAL PLAYS  11,557`), with an optional note.
/// Every tile keeps the same three lines (label, number, note), so tiles in a row line up exactly.
struct StatTile: View {
    let label: String
    let value: String
    var footnote: String?

    init(_ label: String, value: Int, footnote: String? = nil) { self.label = label; self.value = value.grouped; self.footnote = footnote }
    init(_ label: String, text: String, footnote: String? = nil) { self.label = label; self.value = text; self.footnote = footnote }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).linerLabel(size: 10).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.statNumber).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(footnote ?? " ").font(.caption2).foregroundStyle(Palette.label).lineLimit(1)
                .opacity(footnote == nil ? 0 : 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A row of stat tiles that all share the same width and height.
struct StatRow<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: spacing) { content }
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Five hearts: filled white or outlined at 30%. Tapping the current value clears it.
struct HeartRating: View {
    @Binding var rating: Int?
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    rating = rating == n ? nil : n
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: n <= (rating ?? 0) ? "heart.fill" : "heart")
                        .font(.system(size: size))
                        .foregroundStyle(n <= (rating ?? 0) ? Color.white : Color.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(n) heart\(n == 1 ? "" : "s")")
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .contain)
        .accessibilityValue(rating.map { "\($0) of 5" } ?? "Not rated")
    }
}

/// Multi-select chips that wrap onto new lines (moods, filters).
struct ChipGrid: View {
    let options: [String]
    @Binding var selection: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let on = selection.contains(option)
                Button {
                    if on { selection.remove(option) } else { selection.insert(option) }
                } label: {
                    Text(option).font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(on ? Color.black : Color.white)
                        .background(on ? Color.white : Color.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(Palette.stroke))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lays children left to right, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), points)
    }
}

/// The house empty state: a glyph, a serif line and a short explanation.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Palette.faint)
            Text(title).font(.serif(24)).multilineTextAlignment(.center)
            Text(message).font(.callout).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    @Previewable @State var rating: Int? = 3
    @Previewable @State var moods: Set<String> = ["Dreamy"]
    ScrollView {
        VStack(spacing: 16) {
            StatRow { StatTile("Total plays", value: 11_557); StatTile("Minutes", value: 40_210, footnote: "Estimated") }
            HeartRating(rating: $rating)
            ChipGrid(options: ["Euphoric", "Melancholic", "Nostalgic", "Dreamy", "Late Night", "Calm"], selection: $moods)
            EmptyStateView(symbol: "music.note.list", title: "Nothing here yet", message: "Add music in the Music app.")
        }
        .padding()
    }
    .background(.black)
}
