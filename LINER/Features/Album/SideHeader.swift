import SwiftUI

/// "SIDE A ———— 21 min" above each side of an ordinary tracklist, matching the gatefold sleeve. The sides are
/// the ones you arranged for the record (`VinylSides`), or the two halves when you haven't.
struct SideHeader: View {
    let side: VinylSide
    /// The side's running time in seconds.
    let duration: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Side \(side.name)").linerLabel(size: 10).fixedSize()
            Rectangle().fill(Palette.stroke).frame(height: 1)
            if duration > 0 {
                Text("\(Int((duration / 60).rounded())) min").font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.faint).fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: 20) {
        ForEach(VinylSides.halves(11), id: \.name) { SideHeader(side: $0, duration: 1260) }
    }
    .padding().background(.black).preferredColorScheme(.dark)
}
