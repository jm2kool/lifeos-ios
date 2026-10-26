package com.jm2kool.matinee.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jm2kool.matinee.model.Category
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Persona
import com.jm2kool.matinee.model.TasteProfile
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlin.math.pow
import kotlin.random.Random

/// Your taste: built by the swipe quiz, refined by your ratings, and used for the shows picked for you.
object Taste {
    var profile by mutableStateOf(TasteProfile())
        private set
    var picks by mutableStateOf<List<FilmRef>>(emptyList())         // best match first
        private set
    var loadingPicks by mutableStateOf(false)
        private set
    var picksReady by mutableStateOf(false)                           // a refresh has finished at least once
        private set
    private var picksSignature: String? = null
    var showQuiz by mutableStateOf(false)

    val done: Boolean get() = profile.persona != null
    val shouldOffer: Boolean get() = !done && !profile.skipped

    private var beforeQuiz: TasteProfile? = null

    fun load() { Library.doc.taste?.let { profile = it } }

    private fun save() {
        profile = profile.copy(updatedAt = System.currentTimeMillis())
        Library.storeTaste(profile)
    }

    /// A restored backup brings its character with it.
    fun adopt(t: TasteProfile) {
        profile = t
        picks = emptyList()
    }

    // MARK: Quiz

    fun beginQuiz() {
        // Keep the old character until the new one is ready, so skipping a retake loses nothing.
        beforeQuiz = profile
        profile = TasteProfile(libraryScores = profile.libraryScores, libraryYears = profile.libraryYears,
            librarySignature = profile.librarySignature, libraryFilms = profile.libraryFilms)
    }

    /// Leaving the quiz without finishing puts your previous character back.
    fun abandonQuiz() {
        val old = beforeQuiz ?: return
        beforeQuiz = null
        profile = old
    }

    fun record(film: FilmRef, genres: List<String>, liked: Boolean) {
        val scores = profile.scores.toMutableMap()
        for (g in genres) scores[g] = (scores[g] ?: 0.0) + if (liked) 1.0 else -0.6
        profile = profile.copy(
            seen = profile.seen + 1, scores = scores,
            liked = if (liked) profile.liked + film else profile.liked,
            likedYears = if (liked && film.year != null) profile.likedYears + film.year else profile.likedYears,
            disliked = if (!liked) profile.disliked + film.id else profile.disliked,
        )
    }

    fun skipQuiz() {
        if (beforeQuiz?.persona != null) { abandonQuiz(); return }
        beforeQuiz = null
        profile = profile.copy(skipped = true)
        save()
    }

    fun finish(): Persona {
        beforeQuiz = null
        val p = persona(profile)
        profile = profile.copy(persona = p)
        save()
        picks = emptyList()
        return p
    }

    // MARK: From your library

    /// A fingerprint of the titles that feed the character and the picks, so they're only rebuilt when these change.
    fun signature(): String {
        val d = Library.doc
        val ids = d.favorites.map { "fav:${it.id}" } + d.watchlist.map { it.id } + d.liked.map { it.id } +
            d.ratings.entries.sortedBy { it.key }.map { "${it.key}=${it.value}" }
        return "${ids.size}-${ids.hashCode()}"
    }

    /// Work out your character from what you've saved, liked and rated — no quiz needed.
    suspend fun learnFromLibrary(force: Boolean = false) {
        val sig = signature()
        if ((!force && profile.librarySignature == sig) || !Catalog.hasToken) return
        val d = Library.doc
        val weights = HashMap<String, Double>()
        fun add(id: String, w: Double) { weights[id] = (weights[id] ?: 0.0) + w }
        d.favorites.forEach { add(it.id, 2.0) }
        d.watchlist.forEach { add(it.id, 1.0) }
        d.liked.forEach { add(it.id, 1.2) }
        for ((id, score) in d.ratings) {
            val r = score / 20
            add(id, if (r >= 4) 1.2 else if (r >= 3) 0.4 else if (r <= 2) -0.7 else 0.0)
        }
        val ids = weights.keys.filter { it.startsWith(FilmRef.SHOW_PREFIX) }.take(160)
        if (ids.isEmpty()) return
        val details = coroutineScope {
            ids.chunked(8).flatMap { chunk -> chunk.map { id -> async { id to runCatching { Catalog.detail(id) }.getOrNull() } }.awaitAll() }
        }.mapNotNull { (id, det) -> det?.let { id to it } }.toMap()
        val scores = HashMap<String, Double>()
        val years = ArrayList<Int>()
        for ((id, det) in details) {
            val w = weights[id] ?: 0.0
            val gs = det.genres.filter { it in Catalog.genreNames }
            for (g in gs) scores[g] = (scores[g] ?: 0.0) + w / maxOf(1, minOf(det.genres.size, 3)) * 1.5
            if (w > 0) det.ref.year?.let { years.add(it) }
        }
        if (scores.isEmpty()) return
        profile = profile.copy(libraryScores = scores, libraryYears = years, librarySignature = sig, libraryFilms = details.size)
        // Build (or refresh) the character once there's enough to go on.
        if (profile.persona != null || details.size >= 5) {
            profile = profile.copy(persona = persona(profile))
            picks = emptyList()
        }
        save()
    }

    // MARK: Persona

    private val nouns = mapOf(
        "Romance" to "Romantic", "Comedy" to "Optimist", "Melodrama" to "Heartbreaker", "Mystery" to "Sleuth",
        "Crime" to "Sleuth", "Action" to "Maximalist", "Fantasy" to "Dreamer", "Family" to "Homebody",
        "History & politics" to "Time Traveller",
    )
    private val adjectives = mapOf(
        "Romance" to "Tender-Hearted", "Comedy" to "Cheerful", "Melodrama" to "Soulful", "Mystery" to "Curious",
        "Crime" to "Shady", "Action" to "Adrenaline-Fuelled", "Fantasy" to "Enchanted", "Family" to "Warm",
        "History & politics" to "Old-Soul",
    )
    private val emojis = mapOf(
        "Romance" to "💌", "Comedy" to "😂", "Melodrama" to "🎻", "Mystery" to "🔍", "Crime" to "🕵️",
        "Action" to "💥", "Fantasy" to "🐉", "Family" to "🏡", "History & politics" to "🏯",
    )
    private val blurbs = mapOf(
        "Romance" to "Slow-burn glances, umbrella moments and that first hand-hold in episode eight. You're here for the love story, and proud of it.",
        "Comedy" to "Life's heavy enough — you pick the drama that makes you laugh out loud at 1am.",
        "Melodrama" to "Birth secrets, rival families, tears in the rain. You want to be wrecked, and you keep the tissues close.",
        "Mystery" to "Every episode ends on a cliffhanger and you can't sleep until you know who did it.",
        "Crime" to "Prosecutors, chaebols and morally grey anti-heroes. You root for the clever one, not the good one.",
        "Action" to "Chases, fights and bodyguards who'd take a bullet. You came for the adrenaline.",
        "Fantasy" to "Goblins, gumihos, time slips and fated lovers across lifetimes — the stranger the better.",
        "Family" to "Warm kitchens, big families and the quiet moments that make you call your mother.",
        "History & politics" to "Palaces, scholars and court intrigue. You love a drama that sends you down a history hole after.",
    )

    fun persona(p: TasteProfile): Persona {
        // Quiz swipes and your library both count.
        val combined = HashMap(p.scores)
        p.libraryScores?.forEach { (k, v) -> combined[k] = (combined[k] ?: 0.0) + v }
        val ranked = combined.filter { it.value > 0 }.entries.sortedByDescending { it.value }
        val top = ranked.firstOrNull()?.key ?: "Romance"
        val second = ranked.drop(1).firstOrNull()?.key ?: if (top == "Romance") "Comedy" else "Romance"
        val noun = nouns[top] ?: "Drama Fan"
        var adj = adjectives[second] ?: "Curious"
        if (nouns[second] == noun) adj = adjectives[ranked.drop(2).firstOrNull()?.key ?: "Mystery"] ?: "Curious"
        val leaders = ranked.take(4)
        val maxScore = leaders.firstOrNull()?.value ?: 1.0

        val years = p.likedYears + (p.libraryYears ?: emptyList())
        val avgYear = if (years.isEmpty()) 2016 else years.sum() / years.size
        val era = when {
            avgYear < 2005 -> "Loves the classics"
            avgYear < 2013 -> "Golden-era devotee"
            avgYear < 2019 -> "Modern-era regular"
            else -> "Always on the new stuff"
        }
        val likes = p.liked.size
        val total = likes + p.disliked.size
        val traits = ArrayList<String>()
        if (total > 0) {
            val ratio = likes.toDouble() / total
            traits.add(if (ratio > 0.7) "Easy to please" else if (ratio < 0.35) "Tough crowd" else "Picky in the best way")
        } else Library.averageRating?.let { avg ->
            traits.add(if (avg >= 78) "Easy to please" else if (avg <= 58) "Tough crowd" else "Picky in the best way")
        }
        // Which of the four you lean towards.
        val cats = (p.liked + Library.doc.favorites + Library.doc.watchlist).mapNotNull { it.category }
        cats.groupingBy { it }.eachCount().maxByOrNull { it.value }?.takeIf { it.value >= 3 }?.let { traits.add("${it.key.label} devotee") }
        traits.add(if (ranked.size >= 5) "Genre-hopper" else "Knows what they like")
        if (Library.doc.watchlist.size >= 40) traits.add("Watchlist hoarder")

        return Persona("The $adj $noun", emojis[top] ?: "🎬", blurbs[top] ?: "", leaders.map { it.key },
            leaders.map { it.value / maxScore }, era, traits)
    }

    // MARK: Picked for you

    private data class Seed(val film: FilmRef, val weight: Double)

    /// What you love counts most: your favourites, then shows you scored highly, then your watchlist,
    /// then shows you scored lower. Anything under 50 isn't a seed at all.
    private fun seeds(quizLikes: List<FilmRef>): List<Seed> {
        val d = Library.doc
        val pool = HashMap<String, Seed>()
        fun add(f: FilmRef, w: Double) { if (w > (pool[f.id]?.weight ?: 0.0)) pool[f.id] = Seed(f, w) }
        val known = HashMap<String, FilmRef>()
        (Library.watchedFilms + d.watchlist + d.liked + d.shows.values.map { it.show } + d.currentlyWatching).forEach { known.putIfAbsent(it.id, it) }
        for ((id, score) in d.ratings) {
            if (score < 50 || Library.isComfort(id)) continue
            val f = known[id] ?: continue
            add(f, if (score >= 80) 3 + (score - 80) / 20 else 0.6 + (score - 50) / 30 * 0.8)
        }
        d.watchlist.forEach { add(it, 2.0) }
        quizLikes.forEach { add(it, 2.0) }
        (d.liked + d.currentlyWatching).forEach { add(it, 2.5) }
        d.favorites.forEach { add(it, 6.0) }
        // A weighted draw, so favourites are almost always in and the rest rotate between refreshes.
        return pool.values.map { it to Random.nextDouble(0.0001, 1.0).pow(1 / it.weight) }.sortedByDescending { it.second }.take(14).map { it.first }
    }

    suspend fun refreshPicks(force: Boolean = false) {
        val sig = signature()
        if (!force && picks.isNotEmpty() && sig == picksSignature) return
        if (!Catalog.hasToken) return
        loadingPicks = true
        try {
            val seeds = seeds(profile.liked.takeLast(8))
            // Each recommendation scores the weight of every seed that suggested it, a little more near the top of TMDB's list.
            val results = coroutineScope { seeds.map { s -> async { s.weight to TMDB.recommendations(s.film.id) } }.awaitAll() }
            data class Found(val film: FilmRef, val score: Double, val firstSeen: Int)
            val found = LinkedHashMap<String, Found>()
            var order = 0
            for ((w, list) in results) for ((rank, f) in list.withIndex()) {
                order++
                val add = w * (1 - 0.5 * rank / maxOf(list.size, 1))
                found[f.id] = found[f.id]?.let { it.copy(score = it.score + add) } ?: Found(f, add, order)
            }
            val exclude = (profile.disliked + profile.liked.map { it.id } + seeds.map { it.film.id }).toSet()
            // Only things you haven't seen, saved or rated yet.
            fun isNew(f: FilmRef) = f.id !in exclude && !Library.isWatched(f.id) && !Library.inWatchlist(f.id) &&
                Library.rating(f.id) == null && Library.progress(f.id) == null && !Library.isCurrentlyWatching(f.id)
            var ranked = found.values.filter { isNew(it.film) }
                .sortedWith(compareByDescending<Found> { it.score }.thenBy { it.firstSeen }).map { it.film }
            if (ranked.size < 12) {
                val more = TMDB.discoverGenres((profile.persona?.topGenres ?: emptyList()).take(2))
                ranked = ranked + more.filter { f -> isNew(f) && ranked.none { it.id == f.id } }
            }
            // Keep every category in the mix so each one's filter on Home has picks.
            val perCategory = Category.entries.associateWith { c -> ranked.filter { it.category == c }.take(18) }
            val keep = perCategory.values.flatten().map { it.id }.toSet()
            picksSignature = sig
            picksReady = true
            picks = ranked.filter { it.id in keep }
        } finally {
            loadingPicks = false
        }
    }
}
