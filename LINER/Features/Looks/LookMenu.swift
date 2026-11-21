import SwiftUI

/// The "Style" items in an album's or release's ••• menu: logo, font, square or full-screen cover.
struct LookMenuItems: View {
    let key: String
    let make: (LookRequest.Kind) -> LookRequest
    var showsLayout = true
    @Environment(PassportPresenter.self) private var passports

    var body: some View {
        let store = LookStore.shared
        let look = store.look(key)
        Menu("Style", systemImage: "paintbrush") {
            Button(store.logo(key) == nil ? "Add Logo…" : "Edit Logo…", systemImage: "signature") { passports.look = make(.logo) }
            Button(look.face == nil ? "Choose Font…" : "Font: \(look.face?.family ?? "")", systemImage: "textformat") { passports.look = make(.font) }
            if showsLayout {
                let square = look.layout == .square
                Button(square ? "Full-Screen Cover" : "Square Cover", systemImage: square ? "rectangle.expand.vertical" : "square") {
                    withAnimation(.liner) { store.update(key) { $0.layout = square ? nil : .square } }
                }
            }
        }
    }
}

#Preview {
    Menu("More") { LookMenuItems(key: "preview") { _ in .album(.logo, PreviewData.snapshot.albums[0], snapshot: PreviewData.snapshot) } }
        .environment(PreviewData.passports).preferredColorScheme(.dark)
}
