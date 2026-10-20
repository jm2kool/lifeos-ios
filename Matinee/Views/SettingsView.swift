import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var tmdb = ""
    @State private var serverURL = ""
    @State private var serverKey = ""
    @State private var importing = false
    @State private var importer = Importer()
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
                        Button { router.sheet = .signIn } label: { Label("Sign in with Google, Apple & more", systemImage: "person.crop.circle.badge.plus") }
                    }
                } header: { Text("Account") }

                Section {
                    TextField("https://xxxx.supabase.co", text: $serverURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("anon / publishable key", text: $serverKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save") {
                        auth.serverURL = serverURL; auth.anonKey = serverKey
                        library.toast = Toast(text: "Account server saved", symbol: "server.rack")
                    }
                    .disabled(serverURL == auth.serverURL && serverKey == auth.anonKey)
                } header: { Text("Account server") } footer: {
                    Text("Sign-in uses your own free Supabase project. Add matinee://auth-callback as a redirect URL there, then switch on the providers you want.")
                }

                Section {
                    LabeledContent("Catalog", value: Catalog.usingTMDB ? "TMDB" : "IMDb (free, no key)")
                    SecureField("TMDB API read access token", text: $tmdb)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save token") {
                        UserDefaults.standard.set(tmdb.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "tmdbToken")
                        library.toast = Toast(text: tmdb.isEmpty ? "Using the free catalog" : "TMDB connected", symbol: "film")
                    }
                } header: { Text("Film data") } footer: {
                    Text("Optional. A free TMDB token (themoviedb.org → Settings → API) adds wide backdrops and better recommendations. Films you've already logged keep working either way.")
                }

                Section {
                    Button { importing = true } label: { Label("Import from Letterboxd…", systemImage: "square.and.arrow.down") }
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
                    Text("On letterboxd.com go to Settings → Data → Export, unzip it in Files, then pick diary.csv, watched.csv, ratings.csv, watchlist.csv and the rest.")
                }

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
                serverURL = auth.serverURL; serverKey = auth.anonKey
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await importer.run(urls, into: library) } }
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
