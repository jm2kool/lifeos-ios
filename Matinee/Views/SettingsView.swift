import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var tmdb = ""
    @State private var importing = false
    @State private var importer = Importer()
    @State private var importKind: Importer.Kind?
    @State private var confirmErase = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let s = auth.session {
                        HStack(spacing: 14) {
                            Avatar(profile: Profile(name: s.name ?? s.email ?? "", avatar: s.avatar), size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name ?? s.email ?? "Signed in").font(.headline)
                                Text([s.email, s.provider.map { "via \($0.capitalized)" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                        }
                        Label("Diary, lists and ratings sync to your account", systemImage: "icloud.and.arrow.up").font(.footnote).foregroundStyle(Theme.dim)
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    } else {
                        Text("You're using Matinee without an account. Everything stays on this iPhone.").font(.footnote).foregroundStyle(Theme.dim)
                        Button { router.sheet = .signIn } label: { Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus") }
                    }
                } header: { Text("Account") }

                Section {
                    LabeledContent("TMDB", value: Catalog.hasToken ? "Connected" : "Not connected")
                    SecureField("TMDB API read access token", text: $tmdb)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save token") {
                        Catalog.setToken(tmdb)
                        library.toast = Toast(text: Catalog.hasToken ? "TMDB connected" : "TMDB token removed", symbol: "film")
                    }
                } header: { Text("Film data") } footer: {
                    Text("Films, posters and cast come from TMDB. Get a free API Read Access Token at themoviedb.org → Settings → API and paste it here.")
                }

                Section {
                    Button { importKind = nil; importing = true } label: { Label("Import from Letterboxd…", systemImage: "square.and.arrow.down") }
                        .disabled(importer.running)
                    Button { importKind = .ratings; importing = true } label: { Label("Import my Letterboxd ratings…", systemImage: "star.leadinghalf.filled") }
                        .disabled(importer.running)
                    if importer.running {
                        ProgressView(value: Double(importer.done), total: Double(max(importer.total, 1))) {
                            Text("Matching films… \(importer.done)/\(importer.total)").font(.caption)
                        }
                    }
                    if let s = importer.summary {
                        Text(s).font(.footnote).foregroundStyle(Theme.dim)
                        if !importer.unmatched.isEmpty {
                            DisclosureGroup("Unmatched") {
                                ForEach(importer.unmatched, id: \.self) { Text($0).font(.caption) }
                            }
                        }
                    }
                    if let url = exportURL() {
                        ShareLink(item: url) { Label("Export my library (JSON)", systemImage: "square.and.arrow.up") }
                    }
                } header: { Text("Your data") } footer: {
                    Text("On letterboxd.com go to Settings → Data → Export, unzip it in Files, then pick diary.csv, watched.csv, ratings.csv, watchlist.csv and the rest. For ratings only, pick ratings.csv — rated films are added to your films too.")
                }

                WidgetSettingsSection()

                Section {
                    Button("Erase library", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Matinee \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · An independent film diary. Not affiliated with Letterboxd.")
                }
            }
            .oledBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .onAppear {
                tmdb = UserDefaults.standard.string(forKey: "tmdbToken") ?? ""
            }
            .sheet(isPresented: $importing) {
                // Ratings: pick ratings.csv with one tap. Full import: select several CSVs, then Open.
                CSVPicker(multiple: importKind == nil) { urls in
                    let kind = importKind
                    Task { await importer.run(urls, into: library, forceKind: kind) }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Erase your whole library?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { library.eraseAll() }
            } message: { Text("Diary, ratings, likes, watchlist and lists will be removed. You can undo right after.") }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { auth.signOut(); dismiss() }
            } message: { Text("Your library stays on this iPhone.") }
        }
    }

    private func exportURL() -> URL? {
        guard let data = try? Library.encoder.encode(library.doc) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("matinee-library.json")
        try? data.write(to: url)
        return url
    }
}

/// Whether the home-screen widget can see your watchlist, and the one-time server setup if not.
struct WidgetSettingsSection: View {
    @Environment(Library.self) private var library
    @State private var copied = false
    private var sync: WatchlistWidget { WatchlistWidget.shared }

    var body: some View {
        Section {
            HStack {
                Text("Watchlist pick widget")
                Spacer()
                status
            }
            if sync.status == .needsSetup {
                Text("Sideloaded builds can't share files with the widget, so the app sends your watchlist through your account server instead. That needs one table there:")
                    .font(.footnote).foregroundStyle(Theme.dim)
                Button {
                    UIPasteboard.general.string = SharedStore.setupSQL
                    copied = true
                } label: { Label(copied ? "Copied — paste it into Supabase" : "Copy setup SQL", systemImage: copied ? "checkmark" : "doc.on.doc") }
                Text("In supabase.com open your project → SQL Editor → New query, paste, tap Run. Then come back and tap Sync now.")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
            Button("Sync now", systemImage: "arrow.clockwise") { sync.publish(library.doc.watchlist, force: true) }
                .disabled(sync.status == .syncing)
        } header: { Text("Widget") } footer: {
            Text("After it says Working, long-press the widget → Edit Widget or remove and re-add it if it still shows the empty message.")
        }
        .task { if sync.status == .unknown { sync.publish(library.doc.watchlist, force: true) } }
    }

    @ViewBuilder private var status: some View {
        switch sync.status {
        case .ok: Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.watch)
        case .syncing, .unknown: ProgressView()
        case .needsSetup: Label("Needs setup", systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.accent)
        case .offline: Label("Couldn't reach server", systemImage: "wifi.exclamationmark").foregroundStyle(Theme.accent)
        case .noServer: Text(sync.sharedFolder ? "Working" : "No account server").foregroundStyle(sync.sharedFolder ? Theme.watch : Theme.accent)
        }
    }
}
