import SwiftUI

/// First launch: asks for Apple Music access, or explains how to turn it back on.
struct PermissionView: View {
    @Environment(LibraryService.self) private var library
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.stroke))
                .accessibilityHidden(true)
            Text(AppBrand.name).font(.serif(64))
            Text(AppBrand.tagline).linerLabel()
            Text(message).font(.title3).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            switch library.status {
            case .denied:
                GlassPillButton(title: "Open Settings", systemImage: "gearshape", prominent: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .restricted:
                EmptyView()
            default:
                GlassPillButton(title: "Connect Apple Music", systemImage: "music.note", prominent: true) {
                    Task { await library.requestAccess() }
                }
            }
            Text("Nothing is ever changed in your library unless you ask.")
                .font(.footnote).foregroundStyle(Palette.label)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.ignoresSafeArea())
    }

    private var message: String {
        switch library.status {
        case .denied: "\(AppBrand.name) needs your Apple Music library to show your history. Turn on Media & Apple Music for \(AppBrand.name) in Settings."
        case .restricted: "Access to the music library is restricted on this iPhone (Screen Time or a profile), so \(AppBrand.name) can't read it."
        default: "Your library, rebuilt around your own history with every artist, album and song: play counts, ratings, notes and recaps."
        }
    }
}

#Preview { PermissionView().environment(LibraryService()).preferredColorScheme(.dark) }
