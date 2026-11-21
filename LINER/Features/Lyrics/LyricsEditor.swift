import SwiftUI

/// Fix a song's lyrics: tap along as each line starts, nudge one line by a tenth of a second, shift them all,
/// change the words, add or remove lines. Lyrics without timings can be timed here too. Saved edits are kept
/// when lyrics refresh, and can be shared as an LRC file.
struct LyricsEditor: View {
    let item: QueueItem
    let original: Lyrics?
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var player
    @State private var lines: [Draft] = []
    @State private var tapAlong = false
    /// The line the next tap times.
    @State private var cursor = 0
    @State private var confirmRevert = false

    struct Draft: Identifiable, Equatable {
        let id = UUID()
        var time: Double
        var text: String
    }

    private var isCurrentSong: Bool { player.current?.id == item.id }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transport
                if tapAlong { tapPanel }
                List {
                    Section {
                        ForEach($lines) { $line in row($line) }
                            .onDelete { lines.remove(atOffsets: $0) }
                        Button("Add a Line", systemImage: "plus") {
                            lines.append(Draft(time: (lines.last?.time ?? 0) + 3, text: ""))
                        }
                    } header: { shiftAll }
                    Section {
                        ShareLink(item: lrc, preview: SharePreview("\(item.title).lrc")) { Label("Share as LRC", systemImage: "square.and.arrow.up") }
                        if item.isLibrary {
                            Button("Use the Original Lyrics", systemImage: "arrow.uturn.backward", role: .destructive) { confirmRevert = true }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Edit Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { LyricsStore.saveEdited(lrc, for: item); dismiss() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Go back to the lyrics LRCLIB has? Your edits will be lost.", isPresented: $confirmRevert, titleVisibility: .visible) {
                Button("Use the Original", role: .destructive) {
                    Task { _ = await LyricsStore.discardEdits(for: item); dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Pieces

    private var transport: some View {
        HStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(isCurrentSong ? player.currentTime.lyricStamp : "–:––").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 72, alignment: .leading)
            Spacer()
            Button { player.seek(to: player.currentTime - 5) } label: { Image(systemName: "gobackward.5") }
            Button { isCurrentSong ? player.togglePlayPause() : player.play([item], openPlayer: false) } label: {
                Image(systemName: isCurrentSong && player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            Button { player.seek(to: player.currentTime + 5) } label: { Image(systemName: "goforward.5") }
            Spacer()
            Toggle("Tap along", isOn: $tapAlong.animation(.liner)).toggleStyle(.button).font(.subheadline)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    /// Tap the big button as each line starts.
    private var tapPanel: some View {
        VStack(spacing: 8) {
            Text(lines.indices.contains(cursor) ? (lines[cursor].text.isEmpty ? "♪" : lines[cursor].text) : "All lines timed")
                .font(.serif(19)).lineLimit(2).multilineTextAlignment(.center)
            Button {
                guard lines.indices.contains(cursor), isCurrentSong else { return }
                lines[cursor].time = max(0, player.currentTime - 0.15)
                cursor += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text(isCurrentSong ? "This line starts now" : "Play the song first").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.linerPrimary)
            .disabled(!isCurrentSong || !lines.indices.contains(cursor))
            Text("Tap a line below to start from it. Taps are taken a moment early to match how people react.")
                .font(.caption2).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
        }
        .padding(16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var shiftAll: some View {
        HStack {
            Text("Shift all")
            Spacer()
            ForEach([-0.5, -0.1, 0.1, 0.5], id: \.self) { d in
                Button(String(format: "%+.1f", d)) { for i in lines.indices { lines[i].time = max(0, lines[i].time + d) } }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        }
        .textCase(nil)
    }

    private func row(_ line: Binding<Draft>) -> some View {
        let index = lines.firstIndex { $0.id == line.wrappedValue.id } ?? 0
        let active = tapAlong && index == cursor
        return HStack(spacing: 8) {
            Button {
                if tapAlong { cursor = index }
                if isCurrentSong { player.seek(to: max(0, line.wrappedValue.time - 1)) }
            } label: {
                Text(line.wrappedValue.time.lyricStamp).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(active ? Color.black : Palette.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(active ? Color.white : Color.clear))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Starts at \(line.wrappedValue.time.lyricStamp). Play from here")
            TextField("Words", text: line.text, axis: .vertical).font(.system(size: 15))
            Button { line.wrappedValue.time = max(0, line.wrappedValue.time - 0.1) } label: { Image(systemName: "minus") }
                .accessibilityLabel("A tenth earlier")
            Button { line.wrappedValue.time += 0.1 } label: { Image(systemName: "plus") }
                .accessibilityLabel("A tenth later")
            if isCurrentSong {
                Button { line.wrappedValue.time = max(0, player.currentTime - 0.15) } label: { Image(systemName: "stopwatch") }
                    .accessibilityLabel("Starts now")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .semibold))
    }

    // MARK: Data

    private func load() {
        guard lines.isEmpty else { return }
        if let original, original.isSynced {
            lines = original.lines.map { Draft(time: $0.time, text: $0.text) }
        } else if let plain = original?.plain {
            // Untimed lyrics: every line starts at zero until you tap along.
            lines = plain.split(whereSeparator: \.isNewline).map { Draft(time: 0, text: String($0)) }
            tapAlong = true
        }
    }

    /// The lines as LRC, in time order.
    private var lrc: String {
        lines.sorted { $0.time < $1.time }.map { "[\($0.time.lyricStamp)] \($0.text)" }.joined(separator: "\n")
    }
}

extension Double {
    /// "mm:ss.xx", as LRC writes times.
    var lyricStamp: String {
        let t = max(0, self)
        let m = Int(t / 60), s = t - Double(m * 60)
        return String(format: "%02d:%05.2f", m, s)
    }
}

#Preview {
    LyricsEditor(item: .library(PreviewData.snapshot.songs[0]),
                 original: Lyrics(lines: [.init(id: 0, time: 12.3, text: "First line"), .init(id: 1, time: 15.8, text: "Second line")], plain: nil))
        .environment(PreviewData.player).preferredColorScheme(.dark)
}
