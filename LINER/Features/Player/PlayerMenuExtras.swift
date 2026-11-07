import SwiftUI

/// More player ••• items: go to album or artist, Song Passport, and the Vinyl Mode switch.
struct PlayerMenuExtras: View {
    let item: QueueItem?
    @AppStorage("vinylMode") private var vinylMode = false

    var body: some View {
        Toggle(isOn: $vinylMode) { Label("Vinyl Mode", systemImage: "record.circle") }
    }
}
