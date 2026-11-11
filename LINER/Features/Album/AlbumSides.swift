import SwiftUI

/// The sides of a record: the tracklist split in half, Side A first (the longer half when the count is odd).
/// The gatefold sleeve and the ordinary tracklists share it, so "B3" is the same song everywhere.
struct RecordSide: Identifiable, Hashable {
    let name: String
    let range: Range<Int>
    var id: String { name }

    static func split(_ count: Int) -> [RecordSide] {
        let half = (count + 1) / 2
        return count > 1 ? [RecordSide(name: "A", range: 0..<half), RecordSide(name: "B", range: half..<count)]
                         : [RecordSide(name: "A", range: 0..<count)]
    }
}

/// "SIDE A ———— 21 min" above each half of a tracklist.
struct SideHeader: View {
    let side: RecordSide
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
        ForEach(RecordSide.split(11)) { SideHeader(side: $0, duration: 1260) }
    }
    .padding().background(.black).preferredColorScheme(.dark)
}
