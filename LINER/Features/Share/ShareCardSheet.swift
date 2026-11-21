import SwiftUI

/// Preview a share card, choose still or animated, then send it to Instagram Stories, Photos or anywhere.
struct ShareCardSheet: View {
    let content: ShareContent
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryService.self) private var library
    /// Cover (the artwork full bleed) or Passport (a printed passport page).
    @State private var passport = false
    @State private var coverStill: UIImage?
    @State private var passportStill: UIImage?
    @State private var background: UIImage?
    @State private var still: UIImage?
    @State private var video: URL?
    @State private var look = ArtworkLook.neutral
    @State private var animated = true
    @State private var makingVideo = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ZStack {
                    if animated, let video {
                        LoopingVideo(url: video, gravity: .resizeAspect)
                    } else if let still {
                        Image(uiImage: still).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Palette.stroke))
                .frame(maxHeight: .infinity)

                if content.hasPassport {
                    Picker("Style", selection: $passport) {
                        Text("Cover").tag(false)
                        Text("Passport").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: passport) { _, on in
                        still = on ? passportStill : coverStill
                        if on { animated = false }
                    }
                }
                if !passport {
                    Toggle(isOn: $animated) {
                        Label(makingVideo ? "Making the moving version…" : "Animated background", systemImage: "play.rectangle")
                    }
                    .disabled(makingVideo || video == nil)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(Palette.secondary) }

                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        GlassPillButton(title: "Instagram Stories", systemImage: "camera.circle.fill", prominent: true) {
                            Task {
                                let ok = await ShareRenderer.instagram(image: still, video: animated ? video : nil, top: look.dominant, bottom: look.secondary)
                                if ok { dismiss() } else { message = "Instagram isn't installed. Save it or share it another way." }
                            }
                        }
                        HStack(spacing: 10) {
                            GlassPillButton(title: "Save to Photos", systemImage: "square.and.arrow.down") {
                                Task { message = await ShareRenderer.saveToPhotos(image: still, video: animated ? video : nil) ? "Saved to Photos." : "Couldn't save — allow Photos access in Settings." }
                            }
                            if animated, let video {
                                ShareLink(item: video) { Label("Share…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 6) }
                                    .buttonStyle(.linerGlass).controlSize(.large)
                            } else if let still {
                                ShareLink(item: Image(uiImage: still), preview: SharePreview(content.title, image: Image(uiImage: still))) {
                                    Label("Share…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 6)
                                }
                                .buttonStyle(.linerGlass).controlSize(.large)
                            }
                        }
                    }
                }
                .disabled(still == nil)
            }
            .padding(20)
            .background(Palette.background)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        background = await ShareRenderer.backgroundImage(for: content)
        if let background, let key = content.artworkKey { look = await ArtworkAnalysis.look(for: background, key: key) }
        coverStill = ShareRenderer.still(content, background: background)
        if content.hasPassport {
            var covers: [UInt64: UIImage] = [:]
            for id in content.ranked.compactMap(\.albumID) { covers[id] = await ArtworkCache.shared.image(album: id, pixels: 400) }
            let card = PassportCard(content: content, facts: PassportFacts.make(content, library: library), cover: background, look: look, rowCovers: covers)
            let r = ImageRenderer(content: card)
            r.scale = 1
            passportStill = r.uiImage
            // Lists and passports open as a passport; now playing starts on the cover.
            passport = content.kind != .nowPlaying
        }
        still = passport ? passportStill : coverStill
        if passport { animated = false }
        makingVideo = true
        defer { makingVideo = false }
        if let bg = await ShareRenderer.backgroundVideo(for: content, image: background), let overlay = ShareRenderer.overlay(content) {
            video = await ShareRenderer.video(background: bg, overlay: overlay)
        }
        if video == nil || passport { animated = false }
    }
}

/// A share button that opens the sheet for some content.
struct ShareCardButton: View {
    let make: () -> ShareContent
    var label = "Share"
    @State private var content: ShareContent?

    var body: some View {
        Button(label, systemImage: "square.and.arrow.up") { content = make() }
            .sheet(isPresented: Binding(get: { content != nil }, set: { if !$0 { content = nil } })) {
                if let content { ShareCardSheet(content: content) }
            }
    }
}
