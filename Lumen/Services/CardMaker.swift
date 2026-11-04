import Foundation
import PDFKit
import Vision
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@Generable
struct GeneratedDeck {
    @Guide(description: "Flashcards covering the key facts, definitions, formulas and ideas in the notes")
    var cards: [GeneratedCard]
}

@Generable
struct GeneratedCard {
    @Guide(description: "A short, specific question or prompt, answerable from the notes")
    var front: String
    @Guide(description: "The answer, in one or two short sentences or a formula")
    var back: String
}
#endif

/// Makes flashcards from notes. Apple Intelligence on the iPhone first (nothing leaves it); otherwise the
/// `lumen-ai-cards` Edge Function; and with neither, "term: definition" lines become cards.
@MainActor
enum CardMaker {
    struct Draft: Identifiable, Hashable {
        var id = UUID()
        var front: String
        var back: String
        var keep = true
    }

    enum Source: String { case onDevice = "Apple Intelligence", server = "Lumen AI", rules = "Simple rules" }

    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static var onDeviceStatus: String {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return "On this iPhone"
        case .unavailable(.deviceNotEligible): return "Needs an iPhone 15 Pro or newer"
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings"
        case .unavailable(.modelNotReady): return "Getting ready — try again soon"
        case .unavailable: return "Not available"
        }
        #else
        return "Not available"
        #endif
    }

    static func make(from text: String, count: Int, subject: String?, preferServer: Bool = false) async -> (cards: [Draft], source: Source, note: String?) {
        let notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return ([], .rules, "Add some notes first.") }
        var note: String?
        if !preferServer, onDeviceAvailable {
            let cards = await onDevice(notes, count: count, subject: subject)
            if !cards.isEmpty { return (cards, .onDevice, nil) }
            note = "Apple Intelligence couldn't make cards from that, so the server tried."
        }
        if Auth.shared.signedIn {
            do {
                let r = try await API.function("lumen-ai-cards", body: ["text": String(notes.prefix(60_000)), "count": count, "subject": subject ?? ""])
                let cards = (r["cards"] as? [[String: Any]] ?? []).compactMap { c -> Draft? in
                    guard let f = c["front"] as? String, let b = c["back"] as? String, !f.isEmpty, !b.isEmpty else { return nil }
                    return Draft(front: f, back: b)
                }
                if !cards.isEmpty { return (cards, .server, note) }
                note = (r["error"] as? String) ?? "The server didn't return any cards."
            } catch {
                note = "Lumen AI isn't reachable (\(error.localizedDescription)). Used simple rules instead."
            }
        }
        let simple = rules(notes)
        return (simple, .rules, simple.isEmpty ? (note ?? "Write notes as \"term: meaning\" lines, one per line, to make cards without AI.") : note)
    }

    /// Long notes go in chunks that fit the on-device model's context.
    private static func onDevice(_ text: String, count: Int, subject: String?) async -> [Draft] {
        #if canImport(FoundationModels)
        let chunks = chunk(text, size: 3500)
        var out: [Draft] = []
        let perChunk = max(3, Int((Double(count) / Double(chunks.count)).rounded(.up)))
        for piece in chunks where out.count < count {
            let session = LanguageModelSession(instructions: """
                You write excellent study flashcards. Each card tests one idea. Fronts are clear questions; backs are short, \
                correct answers taken only from the notes. Keep formulas as written (use LaTeX like $E = mc^2$ when needed). \
                Never invent facts that aren't in the notes.
                """)
            let prompt = "\(subject.map { "Subject: \($0)\n" } ?? "")Write up to \(perChunk) flashcards from these notes:\n\n\(piece)"
            if let r = try? await session.respond(to: prompt, generating: GeneratedDeck.self) {
                out += r.content.cards.map { Draft(front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines), back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .filter { !$0.front.isEmpty && !$0.back.isEmpty }
            }
        }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.front.lowercased()).inserted }.prefix(count))
        #else
        return []
        #endif
    }

    static func chunk(_ text: String, size: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for para in text.components(separatedBy: "\n") {
            if current.count + para.count > size, !current.isEmpty { out.append(current); current = "" }
            current += para + "\n"
            while current.count > size {
                out.append(String(current.prefix(size)))
                current = String(current.dropFirst(size))
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(current) }
        return out.isEmpty ? [text] : out
    }

    /// "Mitochondria: makes energy for the cell", "Osmosis - movement of water…", "Q: … A: …"
    static func rules(_ text: String) -> [Draft] {
        var out: [Draft] = []
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var i = 0
        while i < lines.count {
            var line = lines[i]
            for bullet in ["- ", "• ", "* ", "– "] where line.hasPrefix(bullet) { line = String(line.dropFirst(bullet.count)) }
            if line.lowercased().hasPrefix("q:"), i + 1 < lines.count, lines[i + 1].lowercased().hasPrefix("a:") {
                out.append(Draft(front: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                                 back: String(lines[i + 1].dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                i += 2
                continue
            }
            for sep in [" :: ", ": ", " — ", " – ", " - ", " = "] {
                if let r = line.range(of: sep) {
                    let term = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                    let def = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                    if term.count >= 1, term.count <= 80, def.count >= 2 {
                        out.append(Draft(front: sep == " = " ? "\(term) = ?" : "What is \(term)?", back: def))
                    }
                    break
                }
            }
            i += 1
        }
        return out
    }
}

/// Text from a PDF or a photo of notes, read on the iPhone.
enum TextExtractor {
    static func pdf(_ url: URL) -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { return "" }
        var out = ""
        for i in 0..<min(doc.pageCount, 80) { out += (doc.page(at: i)?.string ?? "") + "\n" }
        return out
    }

    static func image(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        let orientation = cgOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
