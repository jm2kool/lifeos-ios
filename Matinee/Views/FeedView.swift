import SwiftUI

/// What the people you follow have been watching.
struct FeedView: View {
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @AppStorage(Social.shareActivityKey) private var sharing = false
    private var social: Social { Social.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !auth.signedIn {
                    EmptyState(symbol: "person.2", title: "Sign in to follow people",
                               message: "Follow friends to see what they're watching, and share your own diary if you like.")
                        .padding(.top, 40)
                    Button("Sign in", systemImage: "person.crop.circle") { router.sheet = .signIn }
                        .buttonStyle(.glassProminent).frame(maxWidth: .infinity)
                } else {
                    if social.needsSetup { SocialSetupCard() }
                    if !sharing { ShareActivityCard() }
                    if social.feed.isEmpty {
                        if social.loadingFeed {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            EmptyState(symbol: "person.2", title: social.following.isEmpty ? "Follow someone" : "Nothing yet",
                                       message: social.following.isEmpty ? "Search for @username to find friends, then tap Follow on their profile."
                                                                         : "When the people you follow log films, they show up here.")
                                .padding(.top, 30)
                            if social.following.isEmpty {
                                Button("Find people", systemImage: "magnifyingglass") { router.tab = .search }
                                    .buttonStyle(.glass).frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(social.feed) { item in FeedRow(item: item, person: social.people[item.userID]) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .ambientBackground(Array(social.feed.prefix(3).map(\.film)))
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    JoinPartyButton()
                    if let id = auth.session?.userID {
                        Button("Following", systemImage: "person.2") { router.push(FollowListRoute(userID: id, followers: false, title: "Following")) }
                        Button("Followers", systemImage: "person.2.wave.2") { router.push(FollowListRoute(userID: id, followers: true, title: "Followers")) }
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .refreshable { await social.loadFeed() }
        .task { await social.loadFeed() }
    }
}

/// One shared diary entry: who, what, their rating and review.
struct FeedRow: View {
    let item: FeedItem
    let person: PublicProfile?
    @Environment(Library.self) private var library

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: ProfileRoute(handle: person?.handle ?? "")) {
                Avatar(profile: person?.asProfile ?? Profile(), size: 38)
            }
            .buttonStyle(.plain)
            .disabled(person?.handle == nil)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(person?.name.isEmpty == false ? person!.name : "Someone").font(.subheadline.weight(.bold))
                    Text(item.rewatch ? "rewatched" : "watched").font(.subheadline).foregroundStyle(Theme.dim)
                    Spacer()
                    Text(item.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.dim)
                }
                NavigationLink(value: item.film) {
                    HStack(alignment: .top, spacing: 12) {
                        PosterView(film: item.film, width: 58, corner: 6)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(item.film.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                if let e = item.episode { Text(e).font(.caption.weight(.bold)).foregroundStyle(Theme.accent) }
                            }
                            HStack(spacing: 8) {
                                SmallRating(rating: item.rating)
                                if item.liked { Image(systemName: "heart.fill").foregroundStyle(Theme.heart).font(.caption) }
                                if library.isWatched(item.film.id) {
                                    Label("You've seen it", systemImage: "eye.fill").font(.caption2).foregroundStyle(Theme.watch)
                                } else if library.inWatchlist(item.film.id) {
                                    Label("On your watchlist", systemImage: "clock.fill").font(.caption2).foregroundStyle(Theme.list)
                                }
                            }
                            if !item.review.isEmpty {
                                Text(item.review).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(5).multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .filmContextMenu(item.film)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 20))
    }
}

/// The latest from people you follow, as a row on Home.
struct FriendsShelf: View {
    @Environment(Auth.self) private var auth
    private var social: Social { Social.shared }

    var body: some View {
        Group {
            if auth.signedIn && !social.feed.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Friends are watching", subtitle: "From people you follow") {
                        NavigationLink("See all", value: FeedRoute())
                    }
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(social.feed.prefix(15)) { item in
                                NavigationLink(value: item.film) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        PosterView(film: item.film, width: 108)
                                            .overlay(alignment: .bottomTrailing) {
                                                Avatar(profile: social.people[item.userID]?.asProfile ?? Profile(), size: 28)
                                                    .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                                                    .offset(x: 6, y: 6)
                                            }
                                        HStack(spacing: 4) {
                                            Text(social.people[item.userID]?.handle.map { "@\($0)" } ?? "").font(.caption2.weight(.semibold)).lineLimit(1)
                                            SmallRating(rating: item.rating)
                                        }
                                        .foregroundStyle(Theme.dim)
                                    }
                                    .frame(width: 108, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .filmContextMenu(item.film)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
    }
}

/// Switch on sharing your diary with followers.
struct ShareActivityCard: View {
    @Environment(Library.self) private var library
    @AppStorage(Social.shareActivityKey) private var sharing = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.2.wave.2.fill").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Share your diary with followers?").font(.headline)
                Text("Films you log (with your rating and review) appear in your followers' feeds. Your watchlist and the rest stay private.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                Button("Share my diary") {
                    sharing = true
                    Task { await Social.shared.backfill(library) }
                }
                .buttonStyle(.glassProminent).controlSize(.small).padding(.top, 4)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
    }
}

/// The account server needs the follows, activity and parties tables once.
struct SocialSetupCard: View {
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("One-time setup needed", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Theme.star)
            Text("Following, the feed and watch parties need three tables on your account server. Copy the SQL, then in supabase.com open SQL Editor → New query, paste and Run.")
                .font(.footnote).foregroundStyle(Theme.dim)
            Button(copied ? "Copied" : "Copy setup SQL", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = Social.setupSQL
                copied = true
            }
            .buttonStyle(.glass).controlSize(.small)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
    }
}

/// Followers or following, for anyone.
struct FollowListView: View {
    let route: FollowListRoute
    @State private var people: [PublicProfile] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            if people.isEmpty && loaded {
                EmptyState(symbol: "person.2", title: "No one yet", message: route.followers ? "No followers yet." : "Not following anyone yet.").padding(.top, 60)
            } else if !loaded {
                ProgressView().padding(.top, 80)
            }
            LazyVStack(spacing: 0) { ForEach(people) { PersonRow(person: $0) } }
        }
        .oledBackground()
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            people = await Social.shared.list(route.userID, followers: route.followers)
            loaded = true
        }
    }
}

/// Follow / Following, and counts, on someone's profile.
struct FollowBar: View {
    let profile: PublicProfile
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @State private var counts: (followers: Int, following: Int)?
    private var social: Social { Social.shared }

    var body: some View {
        let following = social.isFollowing(profile.userID)
        VStack(spacing: 10) {
            if let c = counts {
                HStack(spacing: 18) {
                    NavigationLink(value: FollowListRoute(userID: profile.userID, followers: true, title: "Followers")) {
                        Text("**\(c.followers)** followers")
                    }
                    NavigationLink(value: FollowListRoute(userID: profile.userID, followers: false, title: "Following")) {
                        Text("**\(c.following)** following")
                    }
                }
                .font(.subheadline).foregroundStyle(.white.opacity(0.85)).buttonStyle(.plain)
            }
            if profile.userID != auth.session?.userID {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        if following {
                            Button(action: toggle) { Label("Following", systemImage: "checkmark") }.buttonStyle(.glass)
                        } else {
                            Button(action: toggle) { Label("Follow", systemImage: "person.badge.plus") }.buttonStyle(.glassProminent)
                        }
                        NavigationLink(value: BlendRoute(profile: profile)) { Label("Blend", systemImage: "circle.lefthalf.filled") }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .task(id: profile.userID) {
            if auth.signedIn && social.following.isEmpty { await social.refreshFollowing() }
            counts = await social.counts(profile.userID)
        }
    }

    private func toggle() {
        guard auth.signedIn else { router.sheet = .signIn; return }
        Task {
            await social.toggleFollow(profile)
            counts = await social.counts(profile.userID)
        }
    }
}

