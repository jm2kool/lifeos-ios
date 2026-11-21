import SwiftUI

/// DJ mode for a playlist, album or mixtape: for each song, where it starts and ends, how loud it is, a section to
/// loop, and how long it takes to hand over to the next. Plays with these whenever the songs are started from
/// that page.
struct MixEditorView: View {
    let context: String
    let title: String
    let items: [QueueItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var player
    @State private var open: String?

    private var store: MixStore { MixStore.shared }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        DisclosureGroup(isExpanded: Binding(get: { open == item.id }, set: { open = $0 ? item.id : nil })) {
                            controls(item, index: i)
                        } label: {
                            row(item, number: i + 1)
                        }
                    }
                } footer: {
                    Text("Your own files mix seamlessly. Apple Music songs are trimmed and looped by jumping (you may hear a tiny gap), fade between each other rather than overlapping, and can only be made quieter.")
                }
                if store.hasMix(context) {
                    Section { Button("Clear the Mix", role: .destructive) { store.clear(context) } }
                }
            }
            .navigationTitle("DJ Mix · \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Play", systemImage: "play.fill") { player.play(items, mix: context); dismiss() }
                }
            }
        }
    }

    private func row(_ item: QueueItem, number: Int) -> some View {
        let m = store.mix(context, item.id)
        return HStack(spacing: 10) {
            Text("\(number)").font(.serif(15)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).lineLimit(1)
                HStack(spacing: 6) {
                    if m?.start != nil || m?.end != nil { tag("scissors") }
                    if m?.loop != nil { tag("repeat") }
                    if let g = m?.gainDB, g != 0 { Text(String(format: "%+.0f dB", g)).font(.caption2).foregroundStyle(Palette.secondary) }
                    if let t = m?.transition { Text(t == 0 ? "cut" : "\(Int(t)) s fade").font(.caption2).foregroundStyle(Palette.secondary) }
                }
            }
            Spacer()
            Text(item.duration.trackTime).font(.caption).monospacedDigit().foregroundStyle(Palette.secondary)
        }
    }

    private func tag(_ symbol: String) -> some View { Image(systemName: symbol).font(.caption2).foregroundStyle(Palette.secondary) }

    @ViewBuilder private func controls(_ item: QueueItem, index: Int) -> some View {
        let d = max(10, item.duration)
        let m = store.mix(context, item.id) ?? SongMix()
        let start = m.start ?? 0, end = m.end ?? d
        timeSlider("Starts at", value: start, range: 0...max(1, end - 5)) { v in store.update(context, item.id) { $0.start = v < 0.5 ? nil : v } }
        timeSlider("Ends at", value: end, range: min(d - 1, start + 5)...d) { v in store.update(context, item.id) { $0.end = v > d - 0.5 ? nil : v } }
        VStack(alignment: .leading, spacing: 2) {
            Text("Level · \(String(format: "%+.0f dB", m.gainDB))").font(.subheadline)
            Slider(value: Binding(get: { m.gainDB }, set: { v in store.update(context, item.id) { $0.gainDB = v.rounded() } }), in: -12...6, step: 1)
        }
        if index < items.count - 1 {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Own handover into the next song", isOn: Binding(get: { m.transition != nil }, set: { on in
                    store.update(context, item.id) { $0.transition = on ? Automix.seconds : nil }
                }))
                .font(.subheadline)
                if let t = m.transition {
                    Text(t == 0 ? "Straight cut" : "Fade · \(Int(t)) s").font(.caption).foregroundStyle(Palette.secondary)
                    Slider(value: Binding(get: { t }, set: { v in store.update(context, item.id) { $0.transition = v.rounded() } }), in: 0...12, step: 1)
                }
            }
        }
        Toggle("Loop a section", isOn: Binding(get: { m.loop != nil }, set: { on in
            store.update(context, item.id) {
                $0.loop = on ? SongMix.Loop(start: max(start, d * 0.4), end: min(end, d * 0.4 + 8), repeats: 1) : nil
            }
        }))
        .font(.subheadline)
        if let loop = m.loop {
            timeSlider("Loop from", value: loop.start, range: start...max(start + 1, loop.end - 0.5)) { v in
                store.update(context, item.id) { $0.loop?.start = v }
            }
            timeSlider("Loop to", value: loop.end, range: min(end - 0.1, loop.start + 0.5)...end) { v in
                store.update(context, item.id) { $0.loop?.end = v }
            }
            Stepper("Plays \(loop.repeats + 1) times", value: Binding(get: { loop.repeats }, set: { v in
                store.update(context, item.id) { $0.loop?.repeats = v }
            }), in: 1...16)
            .font(.subheadline)
        }
        Button("Play from Here", systemImage: "play.circle") {
            player.play(items, startAt: index, mix: context)
        }
        .font(.subheadline)
    }

    private func timeSlider(_ label: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label) · \(value.trackTime)").font(.subheadline).monospacedDigit()
            Slider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, value)) }, set: { set(($0 * 2).rounded() / 2) }),
                   in: range)
        }
    }
}

#Preview {
    MixEditorView(context: "preview", title: "Preview", items: PreviewData.snapshot.songs.prefix(4).map(QueueItem.library))
        .environment(PreviewData.player).preferredColorScheme(.dark)
}
