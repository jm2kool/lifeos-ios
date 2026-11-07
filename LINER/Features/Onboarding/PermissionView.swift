import SwiftUI

/// The connect screen: shown on the first launch after every install (and after Settings → Recalibrate), so
/// LINER. always asks for Apple Music, wakes the music player and scans the library before you start.
struct PermissionView: View {
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.openURL) private var openURL
    @AppStorage("musicConnected") private var connected = false
    @State private var working = false

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
                if working {
                    HStack(spacing: 10) { ProgressView(); Text("Connecting to Apple Music…").font(.subheadline) }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                } else {
                    GlassPillButton(title: "Connect Apple Music", systemImage: "music.note", prominent: true) {
                        Task { await connect() }
                    }
                }
            }
            Text("Nothing is ever changed in your library unless you ask.")
                .font(.footnote).foregroundStyle(Palette.label)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.ignoresSafeArea())
    }

    private func connect() async {
        working = true
        defer { working = false }
        guard await library.connect() else { return }
        player.recalibrate()
        withAnimation(.liner) { connected = true }
    }

    private var message: String {
        switch library.status {
        case .denied: "\(AppBrand.name) needs your Apple Music library to show your history. Turn on Media & Apple Music for \(AppBrand.name) in Settings."
        case .restricted: "Access to the music library is restricted on this iPhone (Screen Time or a profile), so \(AppBrand.name) can't read it."
        case .authorized: "Connect to Apple Music so \(AppBrand.name) can read your library and play your songs."
        default: "Your library, rebuilt around your own history with every artist, album and song: play counts, ratings, notes and recaps."
        }
    }
}

#Preview { PermissionView().environment(LibraryService()).environment(PreviewData.player).preferredColorScheme(.dark) }
