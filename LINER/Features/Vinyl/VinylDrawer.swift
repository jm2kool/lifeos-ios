import SwiftData
import SwiftUI

/// Opens the crate from anywhere (the Home drawer handle, or double-tapping the Home tab).
@MainActor @Observable
final class CratePresenter {
    static let shared = CratePresenter()
    var isOpen = false

    func open() {
        UserDefaults.standard.set(true, forKey: "vinylMode")
        isOpen = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

/// Home's record drawer handle (Vinyl Mode on): tap or swipe up to pull out the crate.
struct VinylDrawerHandle: View {
    var body: some View {
        Button { CratePresenter.shared.open() } label: {
            VStack(spacing: 6) {
                Capsule().fill(Palette.faint).frame(width: 40, height: 5)
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Your crate").linerLabel(size: 10)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16).padding(.bottom, 6)
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < -20 { CratePresenter.shared.open() } })
        .accessibilityLabel("Open your record crate")
    }
}

/// A record sleeve: the cover with a worn edge and a peek of black vinyl.
struct SleeveView: View {
    let record: VinylRecord
    /// How far the record slides out of the sleeve (fraction of the width).
    var peek: CGFloat = 0.12
    var body: some View {
        GeometryReader { geo in
        ZStack {
            RecordDisc(record: record, side: "A").frame(width: geo.size.width * 0.96).offset(x: geo.size.width * peek)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: peek)
            RecordCover(record: record, cornerRadius: 4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.6), radius: 14, x: 6, y: 10)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The record's art, from the library or a saved cover.
struct RecordCover: View {
    let record: VinylRecord
    var cornerRadius: CGFloat = 0
    var body: some View {
        if let data = record.coverData, let img = UIImage(data: data) {
            FillImage(image: img).clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            ArtworkView(albumID: record.albumID, cornerRadius: cornerRadius)
        }
    }
}
