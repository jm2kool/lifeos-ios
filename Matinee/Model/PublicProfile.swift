import Foundation

/// The part of your profile everyone can see: who you are, your favourites and what you're watching.
/// Your diary, watchlist and ratings never leave your private library row.
struct PublicProfile: Codable, Hashable, Identifiable {
    var userID: String
    var handle: String?
    var name: String
    var bio: String
    var avatarURL: URL?
    var avatarData: Data?                  // a photo you picked, as base64 in the row
    var favorites: [FilmRef] = []
    var favoriteShows: [FilmRef] = []
    var currentlyWatching: [WatchingNow] = []

    var id: String { userID }

    /// A show you've pinned, and the furthest episode you've seen ("S2 E4").
    struct WatchingNow: Codable, Hashable, Identifiable {
        var show: FilmRef
        var lastSeen: String?
        var id: String { show.id }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", handle, name, bio, avatarURL = "avatar_url", avatarData = "avatar_data"
        case favorites, favoriteShows = "favorite_shows", currentlyWatching = "currently_watching"
    }

    init(userID: String, handle: String?, name: String, bio: String, avatarURL: URL?, avatarData: Data?,
         favorites: [FilmRef], favoriteShows: [FilmRef], currentlyWatching: [WatchingNow]) {
        self.userID = userID; self.handle = handle; self.name = name; self.bio = bio
        self.avatarURL = avatarURL; self.avatarData = avatarData
        self.favorites = favorites; self.favoriteShows = favoriteShows; self.currentlyWatching = currentlyWatching
    }

    /// Lenient, so a column added later (or a missing one in a search result) never breaks the profile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(String.self, forKey: .userID)
        handle = try c.decodeIfPresent(String.self, forKey: .handle)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        bio = (try? c.decodeIfPresent(String.self, forKey: .bio)) ?? ""
        avatarURL = (try? c.decodeIfPresent(String.self, forKey: .avatarURL)).flatMap(URL.init(string:))
        avatarData = (try? c.decodeIfPresent(String.self, forKey: .avatarData)).flatMap { Data(base64Encoded: $0) }
        favorites = (try? c.decodeIfPresent([FilmRef].self, forKey: .favorites)) ?? []
        favoriteShows = (try? c.decodeIfPresent([FilmRef].self, forKey: .favoriteShows)) ?? []
        currentlyWatching = (try? c.decodeIfPresent([WatchingNow].self, forKey: .currentlyWatching)) ?? []
    }

    /// Every column is written, nulls included, so clearing your photo or bio clears it for everyone.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encode(handle, forKey: .handle)
        try c.encode(name, forKey: .name)
        try c.encode(bio, forKey: .bio)
        try c.encode(avatarURL?.absoluteString, forKey: .avatarURL)
        try c.encode(avatarData?.base64EncodedString(), forKey: .avatarData)
        try c.encode(favorites, forKey: .favorites)
        try c.encode(favoriteShows, forKey: .favoriteShows)
        try c.encode(currentlyWatching, forKey: .currentlyWatching)
    }

    /// How you appear to others: the profile, favourites and Currently watching from your library.
    @MainActor static func mine(_ library: Library, userID: String) -> PublicProfile {
        let p = library.doc.profile
        let watching = library.currentlyWatching.map { show in
            WatchingNow(show: show, lastSeen: library.progress(show.id)?.lastSeen.map { EpisodeKey.code($0.season, $0.episode) })
        }
        return PublicProfile(userID: userID, handle: Handle.clean(p.handle), name: p.name, bio: p.bio, avatarURL: p.avatar,
                             avatarData: p.avatarData, favorites: library.doc.favorites, favoriteShows: library.favoriteShows,
                             currentlyWatching: watching)
    }

    var asProfile: Profile { Profile(name: name, handle: handle ?? "", bio: bio, avatar: avatarURL, avatarData: avatarData) }
}

/// Usernames: lowercase letters, numbers, dots, dashes and underscores, up to 30. nil when nothing's left.
enum Handle {
    static func clean(_ s: String) -> String? {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.-")
        let h = String(s.lowercased().replacingOccurrences(of: "@", with: "").filter { allowed.contains($0) }.prefix(30))
        return h.isEmpty ? nil : h
    }
}

/// Opens someone's public profile by username.
struct ProfileRoute: Hashable { let handle: String }
