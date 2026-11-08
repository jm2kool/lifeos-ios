import SwiftUI

/// Settings → Listening → Live lyrics log: what the live lyrics card and the keep-alive did, newest first, to
/// share when the card freezes.
struct LiveLyricsLogView: View {
    @State private var entries = LiveLyricsLog.entries.reversed() as [LiveLyricsLog.Entry]

    var body: some View {
        List {
            Section {
                Text("If the card on the Lock Screen freezes, play some music, lock your phone until it does, then come back here and share this log.")
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
            Section {
                if entries.isEmpty { Text("Nothing yet.").foregroundStyle(Palette.secondary) }
                ForEach(entries, id: \.self) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.date.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(Palette.secondary)
                        Text(e.text).font(.footnote)
                            .foregroundStyle(e.text.hasPrefix("⚠︎") ? Color.orange : Color.primary)
                    }
                }
            }
        }
        .navigationTitle("Live lyrics log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: LiveLyricsLog.text) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear", systemImage: "trash") { LiveLyricsLog.clear(); entries = [] }
            }
        }
        .refreshable { entries = LiveLyricsLog.entries.reversed() }
    }
}

#Preview { NavigationStack { LiveLyricsLogView() }.preferredColorScheme(.dark) }
