import SwiftUI

/// Recaps (SPEC §6.12), inside My LINER.: week, month and year recaps from the day recording began, plus All time.
/// Lives in its parent's scroll view and navigation stack.
struct RecapsView: View {
    @Environment(LibraryService.self) private var library
    @State private var history: PlayHistory?
    @State private var kind: RecapPeriod.Kind = .week
    @State private var period: RecapPeriod?
    @State private var showStory = false
    @Namespace private var zoom

    private var periods: [RecapPeriod] {
        guard let b = SnapshotService.shared.baselineDate else { return [] }
        return RecapPeriod.all(kind, since: b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker("Period", selection: $kind) {
                ForEach(RecapPeriod.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 16)

            periodPicker
            content
            AllTimeCard().padding(.horizontal, 16)
        }
        .task(id: library.snapshot.scannedAt) { await reload() }
        .onChange(of: kind) { period = periods.first }
        .fullScreenCover(isPresented: $showStory) {
            if let history, let p = period ?? periods.first {
                RecapStoryView(recap: Recap.make(p, history: history, moods: RecapLoader.moods()))
            }
        }
    }

    private func reload() async {
        history = await RecapLoader.history(library: library)
        if period == nil || period?.kind != kind { period = periods.first }
        if Demo.scene == "recap", history != nil, !showStory {
            try? await Task.sleep(for: .seconds(1.6))
            showStory = true
        }
    }

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(periods) { p in
                    Button { withAnimation(.liner) { period = p } } label: {
                        Text(p.isCurrent ? "This \(kind.rawValue.lowercased())" : p.title)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(period == p ? Color.black : Color.white)
                            .background(period == p ? Color.white : Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var content: some View {
        if SnapshotService.shared.baselineDate == nil || history == nil {
            EmptyStateView(symbol: "calendar.badge.clock", title: "Recaps start today",
                           message: "\(AppBrand.name) records your listening from now on. Apple only shares all-time play counts, so nothing before today can be counted — and nothing is made up.")
        } else if let history, let p = period ?? periods.first {
            let recap = Recap.make(p, history: history, moods: RecapLoader.moods())
            if recap.isEmpty {
                EmptyStateView(symbol: "waveform", title: "Nothing yet for \(p.isCurrent ? "this \(kind.rawValue.lowercased())" : p.title)",
                               message: "Listen in \(AppBrand.name) or the Music app; plays are picked up each time you open \(AppBrand.name).")
            } else {
                RecapSummary(recap: recap, namespace: zoom) { showStory = true }
            }
        }
    }
}

/// All time: straight from the library's play counts.
struct AllTimeCard: View {
    @Environment(LibraryService.self) private var library
    var body: some View {
        Card {
            Text("All Time").font(.sectionTitle)
            HStack(spacing: 12) {
                VStack(alignment: .leading) { Text("Plays").linerLabel(size: 10); Text(library.stats.totalPlays.grouped).font(.statNumber) }
                Spacer()
                VStack(alignment: .leading) { Text("Minutes").linerLabel(size: 10); Text(library.stats.totalMinutes.grouped).font(.statNumber) }
            }
            if let a = library.stats.artists.first { Text("Top artist: \(a.name)").font(.footnote).foregroundStyle(Palette.secondary) }
            Text("Minutes estimated from track durations × play counts").font(.caption2).foregroundStyle(Palette.label)
        }
    }
}

#Preview { NavigationStack { ScrollView { RecapsView() } }.environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
