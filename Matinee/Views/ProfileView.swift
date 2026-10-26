import SwiftUI
import UIKit
import CoreMotion
import PhotosUI

struct ProfileView: View {
    @AppStorage(FilmRatingStyle.key) private var filmStyle: FilmRatingStyle = .score
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @Environment(Taste.self) private var taste
    @State private var meshColors: [Color] = FavoritesMesh.fallback
    @State private var learning = false

    private var characterSource: String {
        let n = taste.profile.libraryFilms
        let quiz = taste.profile.seen > 0
        switch (quiz, n) {
        case (true, let n?) where n > 0: return "From your swipe quiz and \(n) films you've saved, rated or liked."
        case (false, let n?) where n > 0: return "Worked out from \(n) films you've saved, rated or liked."
        default: return "From your swipe quiz."
        }
    }

    var body: some View {
        let p = library.doc.profile
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Identity
                VStack(spacing: 10) {
                    Button { router.sheet = .editProfile } label: { Avatar(profile: p, size: 92) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit profile photo")
                    Text(p.name.isEmpty ? "Film fan" : p.name).font(.title.weight(.bold))
                    HStack(spacing: 6) {
                        if !p.handle.isEmpty { Text("@\(p.handle)") }
                        if let prov = auth.session?.provider { Text("·"); Label(prov.capitalized, systemImage: "checkmark.seal.fill").labelStyle(.titleAndIcon) }
                        else if !auth.signedIn { Text("· On this iPhone only") }
                    }
                    .font(.subheadline).foregroundStyle(Theme.dim)
                    if !p.bio.isEmpty { Text(p.bio).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 30) }
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button("Edit profile", systemImage: "pencil") { router.sheet = .editProfile }.buttonStyle(.glass)
                            if !auth.signedIn {
                                Button("Sign in to sync", systemImage: "icloud") { router.sheet = .signIn }.buttonStyle(.glassProminent)
                            } else if let h = Handle.clean(p.handle), let url = URL(string: "matinee://u/\(h)") {
                                ShareLink(item: url) { Label("Share profile", systemImage: "square.and.arrow.up") }.buttonStyle(.glass)
                            }
                        }
                    }
                    .padding(.top, 4)
                    if !auth.signedIn {
                        Text("Sign in to share your profile. Until then it stays on this iPhone.")
                            .font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 30)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

                // Stats
                HStack(spacing: 0) {
                    stat(library.watchedFilms.count, "Films", .watched)
                    stat(library.thisYearCount, "This year", nil)
                    stat(library.doc.lists.count, "Lists", nil)
                    stat(library.doc.watchlist.count, "Watchlist", .watchlist)
                }
                .padding(.vertical, 16)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal, 16)

                if !library.currentlyWatching.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Currently watching", subtitle: "On your public profile")
                        WatchingNowRow(items: PublicProfile.mine(library, userID: "").currentlyWatching)
                    }
                }

                favorites

                ratings

                if !library.allTags.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Tags")
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(library.allTags, id: \.self) { t in
                                    NavigationLink(value: CollectionRoute.tag(t)) { Text("#\(t)").font(.subheadline.weight(.semibold)) }
                                        .buttonStyle(.glass)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                if !library.doc.liked.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Likes") { NavigationLink("See all", value: CollectionRoute.liked) }
                        PosterRow(films: Array(library.doc.liked.reversed().prefix(12)), width: 92)
                    }
                }

                // Your film character lives at the very bottom.
                if let persona = taste.profile.persona {
                    VStack(alignment: .leading, spacing: 10) {
                        PersonaCard(persona: persona)
                        Text(characterSource).font(.caption).foregroundStyle(Theme.dim).padding(.leading, 6)
                        Button("Retake the swipe quiz") { taste.showQuiz = true }
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                            .padding(.leading, 6)
                    }
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 10) {
                        Button { taste.showQuiz = true } label: {
                            Label("Find your film character", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                        if !library.doc.watchlist.isEmpty || !library.doc.ratings.isEmpty {
                            Button {
                                Task { learning = true; await taste.learnFromLibrary(library, force: true); learning = false }
                            } label: {
                                Label(learning ? "Reading your films…" : "Work it out from my watchlist", systemImage: "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .disabled(learning)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
        .background {
            // Like Apple Card: a slowly shifting blend of colour — here drawn from your favourite posters.
            ZStack(alignment: .top) {
                Color.black
                FavoritesMesh(colors: meshColors)
                    .frame(height: 620)
                    .overlay(Color.black.opacity(0.18))
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .task(id: library.allFavorites.map { $0.poster?.absoluteString ?? $0.id }) { await refreshMesh() }
        // Your character keeps learning from your watchlist and ratings.
        .task(id: Taste.signature(library)) {
            try? await Task.sleep(for: .seconds(1))
            await taste.learnFromLibrary(library)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "gearshape") { router.sheet = .settings } }
        }
    }

    private func refreshMesh() async {
        // Up to four colours from every favourite poster (and its backdrop), so the card mixes all of them.
        var ui: [UIColor] = []
        for f in library.allFavorites {
            for url in [f.largePoster ?? f.poster, f.backdrop] {
                guard let p = await Palette.of(url) else { continue }
                ui += p.uiColors.prefix(url == f.backdrop ? 2 : 4)
            }
        }
        var vivid: [Color] = []
        for c in ui {
            let v = c.adjusted(maxBrightness: 0.95, minSaturation: 0.5, minBrightness: 0.55)
            // Skip near-duplicates so the mix keeps its variety.
            if !vivid.isEmpty, ui.count > 6, vivid.contains(where: { Self.close(UIColor($0), v) }) { continue }
            vivid.append(Color(uiColor: v))
        }
        withAnimation(.easeInOut(duration: 1.2)) { meshColors = vivid.isEmpty ? FavoritesMesh.fallback : vivid }
    }

    private static func close(_ a: UIColor, _ b: UIColor) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: nil); b.getRed(&r2, green: &g2, blue: &b2, alpha: nil)
        return abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2) < 0.18
    }

    private func stat(_ n: Int, _ label: String, _ route: CollectionRoute?) -> some View {
        let content = VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }.frame(maxWidth: .infinity)
        return Group {
            if let route { NavigationLink(value: route) { content }.buttonStyle(.plain) } else { content }
        }
    }

    /// Up to eight films and shows in one grid that's only as big as it needs to be. Edit them in Settings.
    @ViewBuilder private var favorites: some View {
        let list = library.allFavorites
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Favourites") {
                Button(list.isEmpty ? "Add" : "Edit") { router.sheet = .editFavorites }
            }
            if list.isEmpty {
                Text("Pick up to eight films and shows to show off on your profile.")
                    .font(.subheadline).foregroundStyle(Theme.dim).padding(.horizontal, 20)
            } else {
                FavoritesRow(films: list)
            }
        }
    }

    private var ratings: some View {
        let bins = library.ratingHistogram
        let peak = max(1, bins.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Ratings", subtitle: library.averageRating.map {
                filmStyle == .stars ? "Average \(Score.toStars($0).formatted(.number.precision(.fractionLength(1)))) ★ across \(library.watchedRatings.count) films"
                    : "Average score \(Int($0.rounded())) across \(library.watchedRatings.count) films"
            } ?? "Rate films to see your spread")
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<10, id: \.self) { i in
                    NavigationLink(value: CollectionRoute.rated(i)) {
                        VStack(spacing: 4) {
                            if bins[i] > 0 { Text("\(bins[i])").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.dim) }
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Score.color(Double(i * 10 + 5)).opacity(bins[i] == 0 ? 0.12 : bins[i] == peak ? 1 : 0.55))
                                .frame(height: max(4, 80 * CGFloat(bins[i]) / CGFloat(peak)))
                            // Each band of ten points is one half star.
                            Text(filmStyle == .stars ? (i % 2 == 1 ? "\((i + 1) / 2)★" : " ") : "\(i * 10 + 10)")
                                .font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(bins[i] == 0)
                }
            }
            .frame(height: 112, alignment: .bottom)
            .padding(.horizontal, 20)
        }
    }
}

struct ProfileEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var p = Profile()
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Avatar(profile: p, size: 96)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white).frame(width: 30, height: 30)
                                        .background(Theme.accent, in: .circle)
                                        .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                                }
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 18) {
                            PhotosPicker(p.avatarData == nil ? "Choose photo" : "Change photo", selection: $photo, matching: .images)
                                .font(.subheadline.weight(.semibold))
                            if p.avatarData != nil || p.avatar != nil {
                                Button("Remove", role: .destructive) { p.avatarData = nil; p.avatar = nil }
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                Section("Name") { TextField("Your name", text: $p.name) }
                Section {
                    TextField("username", text: $p.handle).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Username") } footer: {
                    Text("People find you by this. Letters, numbers, dots, dashes and underscores.")
                }
                Section("Bio") { TextField("A line about your taste", text: $p.bio, axis: .vertical).lineLimit(2...5) }
            }
            .oledBackground()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        p.handle = Handle.clean(p.handle) ?? ""
                        library.setProfile(p)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .onAppear { p = library.doc.profile }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let small = Self.avatarJPEG(data) {
                        withAnimation(.smooth) { p.avatarData = small }
                    }
                    photo = nil
                }
            }
        }
    }

    /// A square, centre-cropped 320px JPEG — small enough to sync with the library.
    static func avatarJPEG(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let side = min(img.size.width, img.size.height)
        let crop = CGRect(x: (img.size.width - side) / 2, y: (img.size.height - side) / 2, width: side, height: side)
        let out: CGFloat = 320
        let r = UIGraphicsImageRenderer(size: CGSize(width: out, height: out))
        let squared = r.image { _ in
            img.draw(in: CGRect(x: -crop.minX * out / side, y: -crop.minY * out / side,
                                width: img.size.width * out / side, height: img.size.height * out / side))
        }
        return squared.jpegData(compressionQuality: 0.8)
    }
}

/// Your favourite films and shows, up to eight: drag to reorder, remove, or add more. Opened from Settings or your profile.
struct FavoritesEditor: View {
    var asSheet = false
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        let list = library.allFavorites
        List {
            Section {
                ForEach(list) { f in
                    HStack(spacing: 12) {
                        PosterView(film: f, width: 40, corner: 4, glows: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(.body.weight(.semibold)).lineLimit(1)
                            Text([f.isShow ? "Show" : "Film", f.yearText].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .onMove { library.moveFavorites(from: $0, to: $1) }
                .onDelete { rows in rows.map { list[$0] }.forEach(library.removeFavorite) }
                if !library.favoritesFull {
                    Button { adding = true } label: { Label("Add a film or show", systemImage: "plus") }
                }
            } footer: {
                Text(list.isEmpty ? "Pick up to \(LibraryDoc.maxFavorites) films and shows to show on your profile."
                     : "\(list.count) of \(LibraryDoc.maxFavorites). Drag to reorder — they show on your profile in this order.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .oledBackground()
        .navigationTitle("Favourites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if asSheet { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        }
        .sheet(isPresented: $adding) { FavoritePicker() }
    }
}

/// Search for a film or show to add to your favourites.
struct FavoritePicker: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FilmRef] = []

    /// Before you search: shows you're watching or have finished, and the films you've seen.
    private var yours: [FilmRef] {
        var seen = Set<String>()
        return (library.currentlyWatching + library.showsInProgress + library.watchedFilms).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let pool = (query.isEmpty ? yours : results).filter { !library.isFavorite($0.id) }
                if pool.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: query.isEmpty ? "Search for a film or show" : "No matches",
                               message: "Pick the ones you'd watch again and again.")
                        .padding(.top, 40)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(pool) { f in
                        Button { library.addFavorite(f); dismiss() } label: { PosterView(film: f, corner: 6) }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .oledBackground()
            .navigationTitle("Add a favourite")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search films and shows")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
            .task(id: query) {
                guard !query.isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if let r = try? await Catalog.search(query) { results = r }
            }
        }
    }
}

/// An animated mesh gradient in the spirit of the Apple Card in Wallet: a 4×4 mesh whose points
/// drift, whose colours slowly cycle through every colour of your favourites, and which leans as you tilt the phone.
struct FavoritesMesh: View {
    let colors: [Color]
    static let fallback: [Color] = [Theme.accent, Theme.heart, Color(red: 0.55, green: 0.35, blue: 1), Theme.star, Theme.list]
    @State private var motion = TiltMotion()

    private var palette: [SIMD3<Float>] {
        (colors.isEmpty ? Self.fallback : colors).map { c in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: nil)
            return SIMD3(Float(r), Float(g), Float(b))
        }
    }

    var body: some View {
        let pal = palette
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = Float(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            let tilt = motion.tilt
            MeshGradient(width: 4, height: 4, points: Self.points(t, tilt: tilt), colors: Self.colors(pal, t), smoothsColors: true)
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .accessibilityHidden(true)
    }

    static func points(_ t: Float, tilt: SIMD2<Float>) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for y in 0..<4 {
            for x in 0..<4 {
                var p = SIMD2<Float>(Float(x) / 3, Float(y) / 3)
                let seed = Float(x * 7 + y * 13)
                let edgeX = x == 0 || x == 3, edgeY = y == 0 || y == 3
                // Interior points wander in loops; edge points slide along their edge.
                if !edgeX { p.x += 0.13 * sin(t * (0.42 + seed * 0.011) + seed) + tilt.x * 0.08 }
                if !edgeY { p.y += 0.13 * cos(t * (0.37 + seed * 0.013) + seed * 0.7) + tilt.y * 0.08 }
                out.append(p)
            }
        }
        return out
    }

    /// Each point fades from one palette colour to the next on its own clock.
    static func colors(_ pal: [SIMD3<Float>], _ t: Float) -> [Color] {
        let n = pal.count
        return (0..<16).map { i in
            let phase = t * 0.09 + Float(i) * 0.61
            let k = Int(phase.rounded(.down))
            let f = phase - Float(k)
            let smooth = f * f * (3 - 2 * f)
            let a = pal[((k + i * 3) % n + n) % n], b = pal[((k + 1 + i * 3) % n + n) % n]
            let c = a + (b - a) * smooth
            return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
        }
    }
}

/// Gentle device tilt for parallax, smoothed. No permission needed.
@Observable @MainActor
final class TiltMotion {
    var tilt = SIMD2<Float>(0, 0)
    @ObservationIgnored private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let target = SIMD2<Float>(Float(max(-1, min(1, g.x))), Float(max(-1, min(1, g.y + 0.6))))
            self.tilt += (target - self.tilt) * 0.12
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

// MARK: - Public profiles

/// The still of the episode in "Up to S2 E4", looked up from TMDB.
private struct WatchingNowStill: View {
    let item: PublicProfile.WatchingNow
    @State private var still: URL?

    var body: some View {
        EpisodeStill(still: still, show: item.show, width: 176, corner: 10)
            .task(id: item.lastSeen) {
                guard let (season, number) = Self.parse(item.lastSeen),
                      let eps = try? await Catalog.season(item.show.id, season) else { return }
                still = eps.first { $0.number == number }?.still
            }
    }

    /// "S2 E4" → (2, 4).
    static func parse(_ code: String?) -> (Int, Int)? {
        guard let code else { return nil }
        let nums = code.split { !$0.isNumber }.compactMap { Int($0) }
        return nums.count == 2 ? (nums[0], nums[1]) : nil
    }
}

/// The shows someone has pinned, each with a still from the furthest episode they've seen.
struct WatchingNowRow: View {
    let items: [PublicProfile.WatchingNow]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { w in
                    NavigationLink(value: w.show) {
                        VStack(alignment: .leading, spacing: 6) {
                            WatchingNowStill(item: w)
                            Text(w.show.title).font(.caption.weight(.semibold)).lineLimit(1)
                            if let last = w.lastSeen {
                                Text("Up to \(last)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(width: 176, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .filmContextMenu(w.show)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Favourite posters, four to a row: only the ones picked, no empty slots.
struct FavoritesRow: View {
    let films: [FilmRef]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
            ForEach(films) { f in
                NavigationLink(value: f) { PosterView(film: f, corner: 8) }.buttonStyle(.plain).filmContextMenu(f)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Someone else's profile: who they are, what they're watching and their favourites.
struct PublicProfileView: View {
    let handle: String
    @Environment(Auth.self) private var auth
    @State private var profile: PublicProfile?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            if let p = profile {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 10) {
                        Avatar(profile: p.asProfile, size: 92)
                        Text(p.name.isEmpty ? "Film fan" : p.name).font(.title.weight(.bold))
                        if let h = p.handle { Text("@\(h)").font(.subheadline).foregroundStyle(Theme.dim) }
                        if !p.bio.isEmpty { Text(p.bio).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 30) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    if !p.currentlyWatching.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Currently watching")
                            WatchingNowRow(items: p.currentlyWatching)
                        }
                    }
                    if !p.allFavorites.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Favourites")
                            FavoritesRow(films: p.allFavorites)
                        }
                    }
                    if p.currentlyWatching.isEmpty && p.allFavorites.isEmpty {
                        EmptyState(symbol: "film", title: "Nothing here yet", message: "No favourites or shows picked yet.")
                    }
                }
                .padding(.bottom, 40)
            } else if loaded {
                EmptyState(symbol: "person.crop.circle.badge.questionmark", title: "No one called @\(handle)",
                           message: auth.configured ? "Check the username and try again." : "Add your account server in Settings to see profiles.")
                    .padding(.top, 60)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .ambientBackground(Array((profile?.allFavorites ?? []).prefix(3)))
        .navigationTitle(profile?.handle.map { "@\($0)" } ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let h = profile?.handle, let url = URL(string: "matinee://u/\(h)") {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
            }
        }
        .refreshable { profile = await auth.profile(handle: handle) }
        .task {
            profile = await auth.profile(handle: handle)
            loaded = true
        }
    }
}
