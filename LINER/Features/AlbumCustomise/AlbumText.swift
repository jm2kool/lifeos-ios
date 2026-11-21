import SwiftUI

/// How big the words on album pages are: the tracklist, and the title and facts above it. Set in Customise Album
/// or Settings → Album pages; it applies to every album, release, playlist and mixtape page.
enum AlbumText {
    static let tracklistKey = "albumText.tracklist"
    static let titleKey = "albumText.title"
    /// Albums whose title stays plain text instead of the lettering lifted from the cover (comma-separated ids).
    static let plainTitlesKey = "albumText.plainTitles"
    static let range: ClosedRange<Double> = 0.8...1.6

    static func percent(_ scale: Double) -> String { "\(Int((scale * 100).rounded()))%" }
}

extension EnvironmentValues {
    /// Scale for tracklist rows (song titles, numbers, play counts). 1 everywhere except album-like pages.
    @Entry var tracklistScale: CGFloat = 1
}

extension View {
    /// Applies the chosen tracklist text size to the rows inside.
    func albumTextSizes() -> some View { modifier(AlbumTextSizes()) }
}

private struct AlbumTextSizes: ViewModifier {
    @AppStorage(AlbumText.tracklistKey) private var tracklist = 1.0
    func body(content: Content) -> some View { content.environment(\.tracklistScale, CGFloat(tracklist)) }
}

/// The two text-size sliders, shared by Customise Album and Settings.
struct AlbumTextSizeRows: View {
    @AppStorage(AlbumText.tracklistKey) private var tracklist = 1.0
    @AppStorage(AlbumText.titleKey) private var title = 1.0

    var body: some View {
        slider("Tracklist", value: $tracklist)
        slider("Title", value: $title)
        if tracklist != 1 || title != 1 {
            Button("Reset to standard sizes") { withAnimation(.liner) { tracklist = 1; title = 1 } }
        }
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(AlbumText.percent(value.wrappedValue)).monospacedDigit().foregroundStyle(Palette.secondary)
            }
            Slider(value: value, in: AlbumText.range, step: 0.05) {
                Text("\(label) text size")
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller")
            } maximumValueLabel: {
                Image(systemName: "textformat.size.larger")
            }
            .tint(Color(white: 0.75))
        }
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }
}

#Preview {
    Form { AlbumTextSizeRows() }.preferredColorScheme(.dark)
}
