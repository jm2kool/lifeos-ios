import SwiftUI

/// The Recaps tab. Real recaps need snapshots of your play counts over time, which arrive in Phase 9.
struct RecapsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recaps").font(.serif(44))
                    Text("Week · Month · Year").linerLabel()
                    EmptyStateView(symbol: "calendar.badge.clock", title: "Recaps start soon",
                                   message: "Apple only shares all-time play counts, so \(AppBrand.name) will record your listening from the day recaps are switched on. It never makes up past data.")
                        .padding(.top, 40)
                }
                .padding(16)
            }
            .background(Palette.background)
        }
    }
}

#Preview { RecapsView().preferredColorScheme(.dark) }
