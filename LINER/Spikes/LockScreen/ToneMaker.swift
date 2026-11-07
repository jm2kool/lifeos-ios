@preconcurrency import AVFoundation

/// Makes a local audio file for the AVPlayer half of the lock screen test, so it works without importing anything.
enum ToneMaker {
    /// A soft 90-second A-minor pad, AAC in an .m4a.
    @concurrent
    static func make() async throws -> URL {
        let url = LoopVideoMaker.folder.appending(path: "liner-test-tone.m4a")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        // Scoped so the file is closed (and finished) before the URL is handed back.
        try write(to: url)
        return url
    }

    private static func write(to url: URL) throws {
        let rate = 44_100.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ])
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 44_100
        let notes = [220.0, 261.63, 329.63, 440.0]
        var frame = 0
        for _ in 0..<90 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
                  let channels = buffer.floatChannelData else { throw SpikeError("No audio buffer") }
            buffer.frameLength = chunk
            for i in 0..<Int(chunk) {
                let t = Double(frame + i) / rate
                let swell = 0.6 + 0.4 * sin(2 * .pi * 0.1 * t)
                let fade = min(1, t / 2, (90 - t) / 2)
                var v = 0.0
                for (n, hz) in notes.enumerated() { v += sin(2 * .pi * hz * t + Double(n)) / Double(notes.count) }
                let sample = Float(v * 0.18 * swell * fade)
                for c in 0..<Int(format.channelCount) { channels[c][i] = sample }
            }
            try file.write(from: buffer)
            frame += Int(chunk)
        }
    }
}
