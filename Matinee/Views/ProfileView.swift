import SwiftUI

struct ProfileView: View {
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router

    var body: some View {
        let p = library.doc.profile
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Identity
                VStack(spacing: 10) {
                    Avatar(profile: p, size: 92)
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
                            }
                        }
                    }
                    .padding(.top, 4)
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
            }
            .padding(.bottom, 40)
        }
        .oledBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "gearshape") { router.sheet = .settings } }
        }
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

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Favourite films", subtitle: "Your four. Long-press to change.")
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    if i < library.doc.favorites.count {
                        let f = library.doc.favorites[i]
                        NavigationLink(value: f) { PosterView(film: f, corner: 8) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { router.sheet = .pickFavorite(i) } label: { Label("Replace", systemImage: "arrow.2.squarepath") }
                                Button(role: .destructive) { library.removeFavorite(f) } label: { Label("Remove", systemImage: "minus.circle") }
                            }
                    } else {
                        Button { router.sheet = .pickFavorite(i) } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                                .foregroundStyle(Color.white.opacity(0.25))
                                .aspectRatio(2/3, contentMode: .fit)
                                .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(Theme.dim))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add favourite film")
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var ratings: some View {
        let bins = library.ratingHistogram
        let peak = max(1, bins.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Ratings", subtitle: library.averageRating.map { "Average \($0.formatted(.number.precision(.fractionLength(1)))) ★ across \(library.doc.ratings.count) films" } ?? "Rate films to see your spread")
            HStack(alignment: .bottom, spacing: 4) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.star)
                ForEach(0..<10, id: \.self) { i in
                    NavigationLink(value: CollectionRoute.rated(Double(i + 1) / 2)) {
                        VStack(spacing: 4) {
                            if bins[i] > 0 { Text("\(bins[i])").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.dim) }
                            RoundedRectangle(cornerRadius: 3)
                                .fill(bins[i] == peak && bins[i] > 0 ? Theme.star : Color.white.opacity(bins[i] > 0 ? 0.35 : 0.1))
                                .frame(height: max(4, 80 * CGFloat(bins[i]) / CGFloat(peak)))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(bins[i] == 0)
                }
                Text("★★★★★").font(.caption2).foregroundStyle(Theme.star)
            }
            .frame(height: 100, alignment: .bottom)
            .padding(.horizontal, 20)
        }
    }
}

struct ProfileEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var p = Profile()

    var body: some View {
        NavigationStack {
            Form {
                Section { HStack { Spacer(); Avatar(profile: p, size: 80); Spacer() } }.listRowBackground(Color.clear)
                Section("Name") { TextField("Your name", text: $p.name) }
                Section("Username") {
                    TextField("username", text: $p.handle).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Bio") { TextField("A line about your taste", text: $p.bio, axis: .vertical).lineLimit(2...5) }
            }
            .oledBackground()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { library.setProfile(p); dismiss() }.buttonStyle(.glassProminent)
                }
            }
            .onAppear { p = library.doc.profile }
        }
    }
}

struct FavoritePicker: View {
    let slot: Int
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FilmRef] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                let pool = query.isEmpty ? library.watchedFilms : results
                if pool.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: query.isEmpty ? "Search for a film" : "No matches", message: "Pick one of the films that made you love film.")
                        .padding(.top, 40)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(pool) { f in
                        Button { library.setFavorite(f, slot: slot); dismiss() } label: { PosterView(film: f, corner: 6) }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .oledBackground()
            .navigationTitle("Favourite #\(slot + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all films")
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
