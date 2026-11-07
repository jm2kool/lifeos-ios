import SwiftUI
import UniformTypeIdentifiers

/// Spike A screen: build Living Covers, run both lock screen tests, and record what the lock screen showed.
struct LockScreenSpikeView: View {
    private let spike = NowPlayingSpike.shared
    private let lib = LibrarySpike.shared
    @State private var libraryResult: Verdict = .untested
    @State private var localResult: Verdict = .untested
    @State private var importing = false

    private let options: [(String, Verdict)] = [
        ("Full-screen artwork, and it moves", .works),
        ("Full-screen artwork, but it's still", .partial),
        ("Normal small square artwork", .fails),
        ("Nothing from this song on the lock screen", .fails),
    ]

    var body: some View {
        SpikePage(spike: .lockScreen,
                  intro: "Hands iOS a looping 3:4 video for the lock screen. Run each test twice: once with Low Power Mode off (does full-screen work at all?) and once with it on (iOS itself freezes lock screen animation in Low Power Mode; the in-app player keeps moving). Keep Reduce Motion off.") {
            Card {
                SectionLabel("System support")
                Text("Animated keys this iPhone accepts: \(spike.supportedKeys)").font(.footnote)
                Text(spike.tallSupported ? "3:4 tall artwork is supported." : "3:4 tall artwork is NOT in the supported list — the system will ignore it.")
                    .font(.footnote).foregroundStyle(spike.tallSupported ? .green : .orange)
                Text("Test song: \(lib.selected.map { "\($0.title ?? "?") – \($0.artist ?? "?")" } ?? "none (pick one in Library playback)")")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
            }
            covers
            Card {
                SectionLabel("Options")
                Toggle("Also send 1:1 animated artwork", isOn: Bindable(spike).includeSquare)
                Toggle("Re-apply when the queue player changes", isOn: Bindable(spike).reapplyOnChanges)
            }.font(.subheadline)

            test(number: 1, title: "Library song on applicationQueuePlayer",
                 how: "Tap Start, wait for music, lock the phone and look at the lock screen. Also try pause/play from the lock screen. Come back and tap what you saw.",
                 start: { Task { await spike.startLibrary() } }, result: $libraryResult)

            test(number: 2, title: "Local file on our own AVPlayer (like a mixtape)",
                 how: "Plays a generated test tone (or import a SoundCloud mp3 below). Lock the phone, look, come back and tap what you saw.",
                 start: { Task { await spike.startLocal() } }, result: $localResult)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Import audio file", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Re-apply", systemImage: "arrow.clockwise") { spike.apply(reason: "manual") }
                    Button("Stop", systemImage: "stop.fill") { spike.stopAll() }
                }
                .buttonStyle(.linerGlass).font(.footnote)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav]) { result in
            guard case .success(let url) = result, let local = copyIn(url) else { return }
            Task { await spike.startLocal(file: local) }
        }
        .onChange(of: libraryResult) { combine() }
        .onChange(of: localResult) { combine() }
    }

    private var covers: some View {
        Card {
            SectionLabel("Living Covers")
            if spike.working {
                ProgressView("Rendering 3:4 and 1:1 loops…").font(.footnote)
            } else if let tall = spike.tall {
                HStack(alignment: .bottom, spacing: 12) {
                    Image(uiImage: tall.preview).resizable().aspectRatio(3 / 4, contentMode: .fit).frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if let square = spike.square {
                        Image(uiImage: square.preview).resizable().aspectRatio(1, contentMode: .fit).frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text("3:4 is 1080×1440, 1:1 is 1080×1080, 8 s loop at 30 fps, H.264.").font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Button(spike.tall == nil ? "Make Living Covers" : "Remake from test song") { Task { await spike.prepareCovers() } }
                .buttonStyle(.linerGlass).disabled(spike.working)
        }
    }

    private func test(number: Int, title: String, how: String, start: @escaping () -> Void, result: Binding<Verdict>) -> some View {
        Card {
            HStack {
                SectionLabel("Test \(number)")
                VerdictBadge(verdict: result.wrappedValue)
            }
            Text(title).font(.system(size: 22, design: .serif))
            Text(how).font(.footnote).foregroundStyle(.white.opacity(0.65))
            Button("Start test \(number)", systemImage: "play.fill", action: start)
                .buttonStyle(.linerPrimary).disabled(spike.working)
            ObservationButtons(spike: .lockScreen, question: "Test \(number): what did the lock screen show?", options: options) {
                result.wrappedValue = $0
            }
        }
    }

    /// Both full-screen → works; only one → partly; neither → fails.
    private func combine() {
        guard libraryResult != .untested || localResult != .untested else { return }
        let verdict: Verdict = switch (libraryResult, localResult) {
        case (.works, .works): .works
        case (.fails, .fails): .fails
        case (.untested, let v), (let v, .untested): v == .works ? .partial : v
        default: .partial
        }
        SpikeReport.shared.set(.lockScreen, verdict, because: "library \(libraryResult.rawValue), local \(localResult.rawValue)")
    }

    private func copyIn(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = LoopVideoMaker.folder.appending(path: url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: url, to: dest); return dest } catch {
            SpikeReport.shared.log(.lockScreen, "Import failed: \(error.localizedDescription)")
            return nil
        }
    }
}

#Preview { NavigationStack { LockScreenSpikeView() }.preferredColorScheme(.dark) }
