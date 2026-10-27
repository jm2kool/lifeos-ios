import SwiftUI
import PhotosUI
import Vision
import UIKit

/// Photograph a cinema ticket (or pick a screenshot of a booking): Matinee reads it on the phone, finds the
/// film, and opens the log sheet with the date from the ticket.
struct TicketScanSheet: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var reading = false
    @State private var matches: [FilmRef] = []
    @State private var date: Date?
    @State private var lines: [String] = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 220).clipShape(.rect(cornerRadius: 16)).frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "ticket.fill").font(.system(size: 54)).foregroundStyle(Theme.accent)
                            Text("Log from a ticket").font(.title2.weight(.bold))
                            Text("Take a photo of your cinema ticket, or pick a screenshot of the booking. Matinee reads it on your iPhone and fills in the film and the date.")
                                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    }

                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                                    .buttonStyle(.glassProminent)
                            }
                            PhotosPicker(selection: $photo, matching: .images) {
                                Label("Choose photo", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                    }

                    if reading {
                        HStack(spacing: 10) { ProgressView(); Text("Reading the ticket…").foregroundStyle(Theme.dim) }
                    }

                    if let date, !matches.isEmpty {
                        Label("Watched \(date.formatted(date: .complete, time: .omitted))", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.watch)
                    }

                    if !matches.isEmpty {
                        Text("WHICH FILM?").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
                        ForEach(matches) { f in
                            Button { log(f) } label: {
                                HStack(spacing: 12) {
                                    PosterView(film: f, width: 46, corner: 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.title).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                                        Text(f.yearText).font(.subheadline).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if failed {
                        EmptyState(symbol: "text.viewfinder", title: "Couldn't find the film",
                                   message: "Try a sharper photo with the title in view, or search for it instead.")
                        Button("Search instead", systemImage: "magnifyingglass") { router.sheet = .quickLog }
                            .buttonStyle(.glass).frame(maxWidth: .infinity)
                    }

                    if !lines.isEmpty && (failed || !matches.isEmpty) {
                        DisclosureGroup("What Matinee read") {
                            Text(lines.joined(separator: "\n")).font(.caption.monospaced()).foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote).tint(.white)
                    }
                }
                .padding(20)
            }
            .oledBackground()
            .navigationTitle("Scan ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false
                    if let img { read(img) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { read(img) }
                    photo = nil
                }
            }
        }
    }

    private func read(_ img: UIImage) {
        image = img
        matches = []; date = nil; lines = []; failed = false
        reading = true
        Task {
            let found = await TicketReader.read(img)
            lines = found.map(\.text)
            date = TicketReader.date(in: lines.joined(separator: "\n"))
            var titles: [String] = []
            if let ai = await Intelligence.ticketTitle(lines.joined(separator: "\n")) { titles.append(ai) }
            titles += TicketReader.titleCandidates(found)
            var seen = Set<String>(), out: [FilmRef] = []
            for t in titles.prefix(6) {
                guard let r = try? await Catalog.search(t) else { continue }
                for f in r.prefix(t == titles.first ? 3 : 2) where seen.insert(f.id).inserted { out.append(f) }
                if out.count >= 6 { break }
            }
            withAnimation(.smooth) { matches = out; failed = out.isEmpty; reading = false }
        }
    }

    private func log(_ f: FilmRef) {
        var e = LogEntry(film: f)
        if let date { e.watchedOn = date }
        e.tags = ["cinema"]
        router.sheet = .logDraft(e)
    }
}

/// Text from a photo, read on the phone with Vision.
enum TicketReader {
    struct Line { var text: String; var height: CGFloat }

    static func read(_ image: UIImage) async -> [Line] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([req])
            return (req.results ?? []).compactMap { o -> Line? in
                guard let t = o.topCandidates(1).first?.string else { return nil }
                return Line(text: t, height: o.boundingBox.height)
            }
        }.value
    }

    private static let noise = ["screen", "seat", "row", "audi", "cinema", "cinemas", "ticket", "booking", "gst", "total", "price",
                                "amount", "date", "time", "show", "qty", "pvr", "inox", "cinepolis", "imax", "multiplex", "rs", "inr",
                                "₹", "convenience", "fee", "tax", "id", "qr", "scan", "admit", "gate", "class", "recliner", "gold",
                                "executive", "premium", "booked", "paytm", "bookmyshow", "district", "transaction", "order", "www", "http"]

    /// Lines that look like a title: mostly letters, not ticket boilerplate, biggest text first.
    static func titleCandidates(_ lines: [Line]) -> [String] {
        lines.filter { l in
            let t = l.text.trimmingCharacters(in: .whitespaces)
            let letters = t.filter(\.isLetter).count
            guard t.count >= 2, t.count <= 60, Double(letters) / Double(t.count) > 0.6 else { return false }
            let words = t.lowercased().split { !$0.isLetter && $0 != "₹" }.map(String.init)
            return !words.contains { noise.contains($0) }
        }
        .sorted { $0.height > $1.height }
        .map { clean($0.text) }
        .filter { !$0.isEmpty }
    }

    /// "DUNE: PART TWO (UA) IMAX 2D" → "DUNE: PART TWO"
    private static func clean(_ s: String) -> String {
        var t = s
        for pattern in [#"\((U|UA|A|S|U/A|UA\d+\+?)\)"#, #"\b(IMAX|2D|3D|4DX|ENG|ENGLISH|HINDI|TAMIL|TELUGU|DOLBY|ATMOS)\b"#] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// The first date on the ticket that's in the past year, if any.
    static func date(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        return detector.matches(in: text, range: range).compactMap(\.date)
            .first { $0 <= .now.addingTimeInterval(86_400) && $0 >= yearAgo }
            .map { min($0, .now) }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The system camera, for one photo.
struct CameraPicker: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}
