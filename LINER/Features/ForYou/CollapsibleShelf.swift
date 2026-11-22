import SwiftUI

/// A titled shelf you can fold away by tapping its title. Whether it's folded is remembered per shelf.
struct CollapsibleShelf<Content: View>: View {
    let title: String
    var horizontalPadding: CGFloat = 0
    @ViewBuilder var content: Content
    @AppStorage private var collapsed: Bool

    init(_ title: String, id: String, horizontalPadding: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.title = title
        self.horizontalPadding = horizontalPadding
        self.content = content()
        _collapsed = AppStorage(wrappedValue: false, "shelfCollapsed.\(id)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.liner) { collapsed.toggle() }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 8) {
                    Text(title).font(.sectionTitle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.secondary)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, horizontalPadding)
            .accessibilityLabel(title)
            .accessibilityValue(collapsed ? "Folded" : "Open")
            .accessibilityHint(collapsed ? "Double-tap to show" : "Double-tap to fold away")
            if !collapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) { content }
                        .padding(.horizontal, horizontalPadding)
                }
                .scrollClipDisabled()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    CollapsibleShelf("Made for You", id: "preview") {
        ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 10).fill(.gray).frame(width: 150, height: 150) }
    }
    .padding().preferredColorScheme(.dark)
}
