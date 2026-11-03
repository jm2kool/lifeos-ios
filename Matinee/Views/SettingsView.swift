import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var tmdb = ""
    @State private var importing = false
    @State private var importer = Importer()
    @State private var importKind: Importer.Kind?
    @State private var restoring = false
    @State private var shareFiles: [URL]?
    @State private var confirmErase = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var notice: String?
    @State private var cacheBytes = 0
    @AppStorage(FilmRatingStyle.key) private var filmStyle: FilmRatingStyle = .score
    @AppStorage(Catalog.regionKey) private var region = ""

    /// Countries JustWatch covers, for "Where to watch".
    private static let regions = ["AE", "AR", "AT", "AU", "BE", "BR", "CA", "CH", "CL", "CO", "CZ", "DE", "DK", "EG", "ES", "FI", "FR",
                                  "GB", "GR", "HK", "HU", "ID", "IE", "IL", "IN", "IT", "JP", "KE", "KR", "MX", "MY", "NG", "NL", "NO",
                                  "NZ", "PE", "PH", "PK", "PL", "PT", "RO", "SA", "SE", "SG", "TH", "TR", "TW", "UA", "US", "VN", "ZA"]
        .sorted { Catalog.regionName($0) < Catalog.regionName($1) }

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
                        Button(role: .destructive) { confirmDelete = true } label: {
                            HStack {
                                Text("Delete my account")
                                if deleting { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(deleting)
                    } else {
                        Text("You're using Matinee without an account. Everything stays on this iPhone.").font(.footnote).foregroundStyle(Theme.dim)
                        Button { router.sheet = .signIn } label: { Label("Sign in or create an account", systemImage: "person.crop.circle.badge.plus") }
                    }
                    NavigationLink { AccountServerForm() } label: {
                        LabeledContent {
                            Text(!auth.configured ? "Not set up" : auth.serverIsCustom ? "Your own" : "Built in")
                        } label: { Label("Account server", systemImage: "server.rack") }
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
                    Picker(selection: $region) {
                        Text("Automatic · \(Catalog.regionName(Locale.current.region?.identifier ?? "US"))").tag("")
                        ForEach(Self.regions, id: \.self) { Text(Catalog.regionName($0)).tag($0) }
                    } label: { Label("Where to watch in", systemImage: "globe") }
                    .pickerStyle(.navigationLink)
                } header: { Text("Film data") } footer: {
                    Text("Films, posters and cast come from TMDB. Get a free API Read Access Token at themoviedb.org → Settings → API and paste it here. Streaming, rental and cinema listings are for the country you pick.")
                }

                Section {
                    NavigationLink { FavoritesEditor() } label: {
                        LabeledContent { Text("\(library.allFavorites.count) of \(LibraryDoc.maxFavorites)") } label: {
                            Label("Edit favourites", systemImage: "star")
                        }
                    }
                    YearGoalRow()
                } header: { Text("Profile") } footer: {
                    Text("Up to eight films and shows on your profile. Reorder, add or remove them here.")
                }

                Section {
                    Picker("Rate with", selection: $filmStyle) {
                        Text("Score 1–100").tag(FilmRatingStyle.score)
                        Text("Stars 1–5").tag(FilmRatingStyle.stars)
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Ratings") } footer: {
                    Text("Films, shows, seasons and episodes all use this. Ratings are kept as a score out of 100, so you can switch any time. In stars, each half star is 10 points (★★★★ = 80).")
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
                } header: { Text("Import") } footer: {
                    Text("On letterboxd.com go to Settings → Data → Export, unzip it in Files, then pick diary.csv, watched.csv, ratings.csv, watchlist.csv and the rest. For ratings only, pick ratings.csv — rated films are added to your films too. Importing the same file twice doesn't log anything twice.")
                }

                Section {
                    Button { export { try [Backup.backupFile(library)] } } label: { Label("Back up my library", systemImage: "externaldrive.badge.icloud") }
                    Button { restoring = true } label: { Label("Restore from a backup…", systemImage: "arrow.counterclockwise") }
                    Button { export { try [Backup.diaryCSV(library), Backup.watchlistCSV(library)] } } label: {
                        Label("Export for Letterboxd (CSV)", systemImage: "tablecells")
                    }
                } header: { Text("Backups") } footer: {
                    Text("A backup holds everything — diary, ratings, lists, shows and profile — in one file; save it to Files or iCloud Drive. Restoring adds it to what's here, so nothing is lost. The CSVs work with letterboxd.com/import and any spreadsheet.")
                }

                NotificationSettingsSection()

                FriendsSettingsSection()

                Section {
                    LabeledContent { Text(Intelligence.status) } label: { Label("Apple Intelligence", systemImage: "apple.intelligence") }
                    Button { router.sheet = .ask } label: { Label("Ask Matinee what to watch", systemImage: "sparkles") }
                    Button { router.sheet = .finder(nil) } label: { Label("Find a film from a link or scene", systemImage: "sparkle.magnifyingglass") }
                } header: { Text("On-device intelligence") } footer: {
                    Text("Ask Matinee, the film finder, “Write it up” in the log sheet, ticket reading and your Year in Review summary run on your iPhone with Apple Intelligence. Nothing is sent anywhere. Try “Hey Siri, ask Matinee what to watch”.")
                }

                WidgetSettingsSection()

                Section {
                    LabeledContent {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                    } label: { Label("Posters and film data", systemImage: "internaldrive") }
                    Button("Clear downloaded posters and data") {
                        Catalog.clearCaches()
                        cacheBytes = Catalog.cacheSize
                        library.toast = Toast(text: "Cleared — they'll download again as you browse", symbol: "trash")
                    }
                } header: { Text("Storage") } footer: {
                    Text("Matinee keeps posters and film details so pages open quickly and work offline. Your library isn't touched.")
                }

                Section {
                    NavigationLink { ChangelogView() } label: {
                        LabeledContent { Text(Changelog.installed) } label: { Label("What's new", systemImage: "sparkles") }
                    }
                    Button { startTour() } label: { Label("Take the app tour", systemImage: "play.rectangle.on.rectangle") }
                } header: { Text("About") } footer: {
                    Text("Version \(Changelog.current): \(Changelog.releases.first?.headline ?? "").")
                }

                Section {
                    Button("Erase library", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Matinee \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · An independent film diary. Film data from TMDB; this app isn't endorsed or certified by TMDB. Not affiliated with Letterboxd.")
                }
            }
            .oledBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .onAppear {
                tmdb = UserDefaults.standard.string(forKey: "tmdbToken") ?? ""
            }
            .task { cacheBytes = Catalog.cacheSize }
            .sheet(isPresented: $importing) {
                // Ratings: pick ratings.csv with one tap. Full import: select several CSVs, then Open.
                CSVPicker(multiple: importKind == nil) { urls in
                    let kind = importKind
                    Task { await importer.run(urls, into: library, forceKind: kind) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $restoring) {
                CSVPicker(types: [.json]) { urls in
                    guard let url = urls.first else { return }
                    do { let backup = try Backup.read(url); library.restore(backup) } catch { notice = error.localizedDescription }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(get: { shareFiles != nil }, set: { if !$0 { shareFiles = nil } })) {
                ShareSheet(items: shareFiles ?? []).presentationDetents([.medium, .large]).ignoresSafeArea()
            }
            .alert("Matinee", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(notice ?? "") }
            .confirmationDialog("Erase your whole library?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { library.eraseAll() }
            } message: { Text("Diary, ratings, likes, watchlist and lists will be removed. You can undo right after.") }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { auth.signOut(); dismiss() }
            } message: { Text("Your library stays on this iPhone.") }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete my account", role: .destructive) { deleteAccount() }
            } message: {
                Text("Your account, the library synced to it, your public profile, who you follow and anything you've shared are deleted for good. This iPhone keeps its own copy of your library.")
            }
        }
    }

    /// Makes the files, then opens the share sheet to save or send them.
    private func export(_ make: () throws -> [URL]) {
        do { shareFiles = try make() } catch { notice = "Couldn't make the file: \(error.localizedDescription)" }
    }

    private func deleteAccount() {
        deleting = true
        Task {
            let problem = await auth.deleteAccount()
            deleting = false
            if !auth.signedIn { library.forgetAccount() }
            notice = problem ?? "Your account is deleted. Your library is still on this iPhone; erase it below if you want it gone too."
        }
    }

    private func startTour() {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            router.tour = .welcome
        }
    }
}

/// A target for the year: shown as a ring on your Diary.
struct YearGoalRow: View {
    @Environment(Library.self) private var library

    var body: some View {
        let goal = library.doc.yearGoal
        Picker(selection: Binding(get: { goal ?? 0 }, set: { library.setYearGoal($0 == 0 ? nil : $0) })) {
            Text("None").tag(0)
            ForEach([12, 24, 26, 36, 50, 52, 75, 100, 150, 200, 250, 365], id: \.self) { Text("\($0) films").tag($0) }
            if let g = goal, ![12, 24, 26, 36, 50, 52, 75, 100, 150, 200, 250, 365].contains(g) { Text("\(g) films").tag(g) }
        } label: { Label("\(String(Date.now.year)) goal", systemImage: "target") }
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

/// New episodes and release days.
struct NotificationSettingsSection: View {
    @Environment(Library.self) private var library
    @AppStorage(Reminders.episodesKey) private var episodes = true
    @AppStorage(Reminders.releasesKey) private var releases = true
    @State private var allowed = true

    var body: some View {
        Section {
            Toggle(isOn: $episodes) { Label("New episodes", systemImage: "tv") }
            Toggle(isOn: $releases) { Label("Watchlist releases", systemImage: "film") }
            if !allowed {
                Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: {
                    Label("Notifications are off for Matinee — turn them on", systemImage: "bell.slash")
                }
            }
        } header: { Text("Notifications") } footer: {
            Text("The day a new episode airs for shows you're watching (at 6pm), and the day films on your watchlist or with a reminder come out (at 10am).")
        }
        .onChange(of: episodes) { _, _ in Task { await Reminders.refresh(library, force: true, ask: true); allowed = await Reminders.authorized } }
        .onChange(of: releases) { _, _ in Task { await Reminders.refresh(library, force: true, ask: true); allowed = await Reminders.authorized } }
        .task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            allowed = s.authorizationStatus != .denied
        }
    }
}

/// Sharing your diary and watchlist, and the one-time server setup for friends and parties.
struct FriendsSettingsSection: View {
    @Environment(Library.self) private var library
    @AppStorage(Social.shareActivityKey) private var shareActivity = false
    @AppStorage(Social.shareWatchlistKey) private var shareWatchlist = false
    @State private var copied = false
    @State private var confirmUnshare = false

    var body: some View {
        Section {
            Toggle(isOn: $shareActivity) { Label("Share my diary with followers", systemImage: "person.2.wave.2") }
            Toggle(isOn: $shareWatchlist) { Label("Show my watchlist for Blend", systemImage: "circle.lefthalf.filled") }
            Button {
                UIPasteboard.general.string = Social.setupSQL
                copied = true
            } label: { Label(copied ? "Copied — paste it into Supabase" : "Copy setup SQL", systemImage: copied ? "checkmark" : "doc.on.doc") }
            JoinPartyButton()
            NavigationLink { BlockedPeopleView() } label: {
                LabeledContent { Text(library.blocked.isEmpty ? "No one" : "\(library.blocked.count)") } label: {
                    Label("Blocked", systemImage: "hand.raised")
                }
            }
        } header: { Text("Friends") } footer: {
            Text("Following, the friends feed and watch parties need three tables on your account server: copy the SQL, then in supabase.com open SQL Editor → New query, paste and Run. It also lets you delete your account from the app. Sharing is off until you turn it on.")
        }
        .onChange(of: shareActivity) { old, on in
            if on { Task { await Social.shared.backfill(library) } } else if old { confirmUnshare = true }
        }
        .onChange(of: shareWatchlist) { _, _ in Task { await library.publishProfile() } }
        .confirmationDialog("Take down what you've shared?", isPresented: $confirmUnshare, titleVisibility: .visible) {
            Button("Remove from followers' feeds", role: .destructive) {
                Task {
                    let ok = await Social.shared.unshareAll()
                    library.toast = Toast(text: ok ? "Your shared diary is gone" : "Couldn't reach your account server", symbol: ok ? "eye.slash" : "exclamationmark.triangle")
                }
            }
            Button("Leave it up", role: .cancel) {}
        } message: { Text("New entries won't be shared any more. Entries you shared already can stay, or come down now.") }
    }
}
