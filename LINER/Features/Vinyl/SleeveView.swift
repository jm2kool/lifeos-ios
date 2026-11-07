import SwiftUI

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

#Preview {
    SleeveView(record: .album(PreviewData.snapshot.albums[0], PreviewData.snapshot), peek: 0.3)
        .frame(width: 240, height: 240).padding(60).background(.black)
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
