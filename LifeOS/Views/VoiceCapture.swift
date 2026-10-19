import SwiftUI
import Speech
import AVFoundation

/// Listens and transcribes (on the iPhone when it can). Stops by itself after a short pause.
@MainActor
@Observable
final class Dictation {
    var text = ""
    var listening = false
    var level: Double = 0          // 0…1, for the little meter
    var problem: String?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var quiet: Task<Void, Never>?
    @ObservationIgnored var onFinish: ((String) -> Void)?

    static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start() async {
        guard !listening else { return }
        problem = nil; text = ""
        guard await Self.authorize() else { problem = "Allow the microphone and speech recognition for LifeOS in Settings."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            problem = "Speech recognition isn't available right now."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                req.append(buffer)
                guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
                let rms = sqrt(sum / Float(buffer.frameLength))
                let v = Double(min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 50)))
                Task { @MainActor in self?.level = v }
            }
            engine.prepare()
            try engine.start()
            listening = true
            waitForPause(first: true)
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let said = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                Task { @MainActor in
                    guard let self, self.listening else { return }
                    if let said, !said.isEmpty { self.text = said; self.waitForPause(first: false) }
                    if final || (error != nil && result == nil && !self.text.isEmpty) { self.finish() }
                    else if error != nil && self.text.isEmpty { self.problem = "I didn't hear anything."; self.stop() }
                }
            }
        } catch {
            problem = "Couldn't start the microphone: \(error.localizedDescription)"
            stop()
        }
    }

    /// Finish 1.8 s after you stop talking (8 s if you haven't started), or after a minute in any case.
    private func waitForPause(first: Bool) {
        quiet?.cancel()
        quiet = Task { [weak self] in
            try? await Task.sleep(for: .seconds(first ? 8 : 1.8))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Stops listening and hands over what was said.
    func finish() {
        guard listening else { return }
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        if said.isEmpty { problem = "I didn't hear anything." } else { onFinish?(said) }
    }

    func stop() {
        quiet?.cancel()
        listening = false; level = 0
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The mic at the top of each tab.
struct VoiceButton: View {
    @Environment(Store.self) private var store
    var body: some View {
        Button { store.sheet = .voice } label: { Image(systemName: "mic.fill") }
            .accessibilityLabel("Voice capture")
    }
}

extension View {
    /// Adds the voice capture mic to the top-left of a tab's main screen.
    func voiceCaptureButton() -> some View {
        toolbar { ToolbarItem(placement: .topBarLeading) { VoiceButton() } }
    }
}

/// Tap the mic, speak, and it's filed: a to-do, email draft, calendar event, timetable block, note, link or card.
struct VoiceCaptureSheet: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var dictation = Dictation()
    @State private var filing = false
    @State private var outcome: CaptureOutcome?

    var body: some View {
        VStack(spacing: 16) {
            if let outcome {
                Image(systemName: outcome.review ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 40)).foregroundStyle(outcome.review ? .orange : .green)
                Text(outcome.summary).font(.headline).multilineTextAlignment(.center)
                HStack {
                    Button("Undo") { store.undoLast(); dismiss() }.buttonStyle(.glass)
                    if let f = outcome.friday, !store.assistantAddress.isEmpty {
                        Button("Tell \(store.assistantName)", systemImage: "message.fill") {
                            var c = URLComponents(); c.scheme = "sms"; c.path = store.assistantAddress
                            c.queryItems = [URLQueryItem(name: "body", value: f)]
                            if let u = c.url { openURL(u) }
                            dismiss()
                        }
                        .buttonStyle(.glassProminent)
                    } else if let f = outcome.friday {
                        Button("Message \(store.assistantName)") { dismiss(); store.sheet = .delegate(f) }.buttonStyle(.glassProminent)
                    } else {
                        Button("Done") { dismiss() }.buttonStyle(.glassProminent)
                    }
                }
            } else if filing {
                ProgressView().controlSize(.large)
                Text("“\(dictation.text)”").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4)
                Text("Filing it…").font(.headline)
            } else {
                Meter(level: dictation.level, on: dictation.listening)
                Text(dictation.text.isEmpty ? (dictation.listening ? "Listening…" : " ") : dictation.text)
                    .font(dictation.text.isEmpty ? .headline : .title3).multilineTextAlignment(.center).lineLimit(5)
                    .contentTransition(.opacity).animation(.smooth, value: dictation.text)
                if let p = dictation.problem {
                    Text(p).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try again") { Task { await dictation.start() } }.buttonStyle(.glass)
                } else {
                    Button(dictation.listening ? "Done" : "Listen", systemImage: dictation.listening ? "stop.fill" : "mic.fill") {
                        if dictation.listening { dictation.finish() } else { Task { await dictation.start() } }
                    }
                    .buttonStyle(.glassProminent)
                }
                Text("Say a to-do, an email to draft, a plan for a time, a note or a link.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .task {
            dictation.onFinish = { said in file(said) }
            await dictation.start()
        }
        .onDisappear { dictation.stop() }
    }

    private func file(_ said: String) {
        filing = true
        Task {
            let o = await CaptureFiler.file(said, store: store, assistant: assistant, source: "Voice")
            withAnimation(.smooth) { outcome = o; filing = false }
            store.toast = Toast(text: o.summary, undo: true)
            if o.friday == nil && !o.review {
                try? await Task.sleep(for: .seconds(2.5))
                dismiss()
            }
        }
    }
}

private struct Meter: View {
    let level: Double
    let on: Bool
    var body: some View {
        ZStack {
            Circle().fill(.tint.opacity(0.15)).frame(width: 64 + 40 * level, height: 64 + 40 * level)
            Circle().fill(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)).frame(width: 60, height: 60)
            Image(systemName: "mic.fill").font(.title2).foregroundStyle(.white)
        }
        .frame(height: 110)
        .animation(.smooth(duration: 0.15), value: level)
    }
}
