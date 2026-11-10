import SwiftUI

/// Arrange a record's sides: drag songs up and down, and drag the side dividers between them, to choose what's on
/// Side A, B, C… Add a side, split the record evenly, or go back to the usual two halves. Used by the gatefold,
/// the turntable, the Listening Room and "Put it on".
struct SidesEditor: View {
    let record: VinylRecord
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []

    enum Row: Hashable, Identifiable {
        case side(UUID)
        case track(QueueItem)
        var id: String {
            switch self {
            case .side(let u): "side-\(u.uuidString)"
            case .track(let t): t.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        switch row {
                        case .side: sideHeader(i).moveDisabled(i == 0).deleteDisabled(i == 0)
                        case .track(let t): trackRow(t, at: i).deleteDisabled(true)
                        }
                    }
                    .onMove(perform: move)
                    .onDelete { offsets in rows.remove(atOffsets: offsets) }
                } footer: {
                    Text("Drag a song, or a side's divider, to choose what's on each side. Songs you haven't placed go on the last side.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Sides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save() } }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button("Add a Side", systemImage: "plus") { rows.append(.side(UUID())) }
                        Divider()
                        ForEach(2...4, id: \.self) { n in
                            Button("Split Evenly into \(n) Sides") { split(into: n) }.disabled(tracks.count < n)
                        }
                        Button("Back to Side A and B", systemImage: "arrow.uturn.backward") { split(into: 2) }
                    } label: {
                        Label("Sides", systemImage: "square.split.2x1")
                    }
                }
            }
            .onAppear { if rows.isEmpty { load() } }
        }
    }

    private var tracks: [QueueItem] {
        rows.compactMap { row -> QueueItem? in
            if case .track(let t) = row { return t }
            return nil
        }
    }

    private func sideHeader(_ i: Int) -> some View {
        let letter = VinylSides.letter(rows[..<i].filter { if case .side = $0 { true } else { false } }.count)
        let songs = rows[(i + 1)...].prefix { if case .track = $0 { true } else { false } }
        let minutes = Int((songs.reduce(0.0) { if case .track(let t) = $1 { $0 + t.duration } else { $0 } } / 60).rounded())
        return HStack {
            Text("Side \(letter)").font(.serif(22))
            Spacer()
            Text("\(songs.count) song\(songs.count == 1 ? "" : "s") · \(minutes) min").linerLabel(size: 10)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.white.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    private func trackRow(_ t: QueueItem, at i: Int) -> some View {
        HStack(spacing: 12) {
            QueueItemArtwork(item: t, cornerRadius: 4).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(t.duration.trackTime).font(.caption).foregroundStyle(Palette.secondary).monospacedDigit()
            }
        }
        .accessibilityHint("Drag to move it to another side")
    }

    // MARK: Changes

    private func load() {
        let r = record.sided()
        rows = r.sideList.flatMap { side in [Row.side(UUID())] + r.tracks[side.range].map(Row.track) }
    }

    /// Moves rows, keeping a side divider at the very top (Side A always starts the record).
    private func move(_ from: IndexSet, _ to: Int) {
        rows.move(fromOffsets: from, toOffset: max(1, to))
        if case .track = rows.first, let k = rows.firstIndex(where: { if case .side = $0 { true } else { false } }) {
            rows.insert(rows.remove(at: k), at: 0)
        }
    }

    private func split(into n: Int) {
        let list = tracks
        let size = Int((Double(list.count) / Double(n)).rounded(.up))
        rows = stride(from: 0, to: list.count, by: max(1, size)).flatMap { start in
            [Row.side(UUID())] + list[start..<min(list.count, start + size)].map(Row.track)
        }
        if rows.isEmpty { rows = [.side(UUID())] }
    }

    private func save() {
        var sides: [[String]] = []
        for row in rows {
            switch row {
            case .side: sides.append([])
            case .track(let t): if sides.isEmpty { sides.append([]) }; sides[sides.count - 1].append(t.id)
            }
        }
        let usual = VinylSides.halves(tracks.count).map { Array(tracks[$0.range].map(\.id)) }
        VinylSides.shared.set(sides.filter { !$0.isEmpty } == usual ? nil : sides, for: record.id)
        UISelectionFeedbackGenerator().selectionChanged()
        dismiss()
    }
}

#Preview {
    SidesEditor(record: .album(PreviewData.snapshot.albums[0], PreviewData.snapshot))
        .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
