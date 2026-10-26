package com.jm2kool.matinee.model

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Weekend
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import com.jm2kool.matinee.data.Taste
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

data class Toast(val text: String, val icon: ImageVector, val undo: Boolean = false, val id: String = UUID.randomUUID().toString())

val AppJson = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }

/// Your shows: diary, watchlist, likes, ratings, lists and profile. Saved on the phone only.
object Library {
    var doc by mutableStateOf(LibraryDoc())
        private set
    var toast by mutableStateOf<Toast?>(null)
    private var undoSnapshot: LibraryDoc? = null
    private lateinit var file: File
    private val writer = Executors.newSingleThreadExecutor()

    fun init(context: Context) {
        file = File(context.filesDir, "library.json")
        runCatching { if (file.exists()) doc = AppJson.decodeFromString(LibraryDoc.serializer(), file.readText()) }
        Watching.load(doc.watching)
    }

    // MARK: Reading

    val entries: List<LogEntry> get() = doc.entries.sortedWith(compareByDescending<LogEntry> { it.watchedOn }.thenByDescending { it.createdAt })
    fun entries(id: String) = entries.filter { it.film.id == id }
    fun isWatched(id: String) = doc.watched.any { it.id == id } || doc.entries.any { it.film.id == id }
    fun isLiked(id: String) = doc.liked.any { it.id == id }
    fun inWatchlist(id: String) = doc.watchlist.any { it.id == id }
    fun rating(id: String): Double? = doc.ratings[id]
    /// Comfort shows get watched and logged, but never asked for a rating.
    fun isComfort(id: String) = id in doc.comfort
    val favorites: List<FilmRef> get() = doc.favorites
    fun isFavorite(id: String) = favorites.any { it.id == id }
    val favoritesFull: Boolean get() = favorites.size >= LibraryDoc.MAX_FAVORITES
    val currentlyWatching: List<FilmRef> get() = doc.currentlyWatching
    fun isCurrentlyWatching(id: String) = currentlyWatching.any { it.id == id }

    /// Every distinct show you've watched, newest first.
    val watchedFilms: List<FilmRef>
        get() {
            val seen = HashSet<String>()
            val out = ArrayList<FilmRef>()
            for (e in entries) if (seen.add(e.film.id)) out.add(e.film)
            for (f in doc.watched.asReversed()) if (seen.add(f.id)) out.add(f)
            return out
        }

    val thisYearCount: Int get() { val y = java.time.LocalDate.now().year; return doc.entries.count { Dates.year(it.watchedOn) == y } }

    /// Scores (1–100) of shows you've actually watched.
    val watchedRatings: List<Double>
        get() {
            val ids = (doc.watched.map { it.id } + doc.entries.map { it.film.id }).toSet()
            return doc.ratings.filter { it.key in ids && it.value > 0 }.values.toList()
        }

    /// How many shows sit in each band of ten (index 0 = 1–10 … 9 = 91–100).
    val ratingHistogram: List<Int>
        get() {
            val bins = IntArray(10)
            for (r in watchedRatings) bins[band(r)]++
            return bins.toList()
        }

    fun band(score: Double): Int = ((Math.round(score) - 1) / 10).toInt().coerceIn(0, 9)

    val averageRating: Double? get() = watchedRatings.takeIf { it.isNotEmpty() }?.average()
    val allTags: List<String> get() = doc.entries.flatMap { it.tags }.toSet().sorted()

    // MARK: Writing

    private fun mutate(toastText: String? = null, icon: ImageVector = Icons.Filled.Check, undoable: Boolean = false, change: (LibraryDoc) -> Unit) {
        if (undoable) undoSnapshot = doc
        val d = doc.copy()
        change(d)
        d.updatedAt = System.currentTimeMillis()
        doc = d
        persist()
        if (toastText != null) toast = Toast(toastText, icon, undoable)
    }

    fun undo() {
        val s = undoSnapshot ?: return
        undoSnapshot = null
        doc = s
        Watching.load(s.watching)
        persist()
        toast = Toast("Undone", Icons.AutoMirrored.Filled.Undo)
    }

    fun log(e: LogEntry) = mutate("Logged ${e.film.title}", Icons.Filled.Visibility) { d ->
        d.entries = if (d.entries.any { it.id == e.id }) d.entries.map { if (it.id == e.id) e else it } else d.entries + e
        // An unrated comfort watch leaves any rating you gave before alone.
        val keepRating = e.film.id in d.comfort && e.rating == null
        // The newest viewing sets the show's rating, so clearing it there clears it everywhere.
        val newest = d.entries.filter { it.film.id == e.film.id }.maxWithOrNull(compareBy({ it.watchedOn }, { it.createdAt }))
        if (newest?.id == e.id && !keepRating) d.ratings = d.ratings.set(e.film.id, e.rating?.takeIf { it > 0 })
        else if (e.rating != null && d.ratings[e.film.id] == null) d.ratings = d.ratings + (e.film.id to e.rating)
        if (e.liked && d.liked.none { it.id == e.film.id }) d.liked = d.liked + e.film
        d.watchlist = d.watchlist.filter { it.id != e.film.id }
    }

    fun delete(e: LogEntry) = mutate("Entry deleted", Icons.Filled.Delete, undoable = true) { d ->
        d.entries = d.entries.filter { it.id != e.id }
        // Deleting a diary entry doesn't un-watch the show (use Remove from watched for that).
        if (d.entries.none { it.film.id == e.film.id } && d.watched.none { it.id == e.film.id }) d.watched = d.watched + e.film
    }

    fun toggleWatched(f: FilmRef) {
        if (isWatched(f.id)) {
            // Un-watching wipes everything that says you saw it: diary entries, the rating and the like.
            mutate("Removed from watched", Icons.Outlined.VisibilityOff, undoable = true) { d ->
                d.watched = d.watched.filter { it.id != f.id }
                // Episode progress stays: you still saw those.
                d.entries = d.entries.filter { it.film.id != f.id }
                d.ratings = d.ratings - f.id
                d.liked = d.liked.filter { it.id != f.id }
            }
        } else {
            mutate("Marked as watched", Icons.Filled.Visibility) { d ->
                d.watched = d.watched + f
                d.watchlist = d.watchlist.filter { it.id != f.id }
            }
        }
    }

    fun toggleLike(f: FilmRef) {
        val on = !isLiked(f.id)
        mutate(if (on) "Liked" else null, Icons.Filled.Favorite) { d ->
            if (on) {
                d.liked = d.liked + f
                if (d.watched.none { it.id == f.id } && d.entries.none { it.film.id == f.id }) d.watched = d.watched + f
            } else d.liked = d.liked.filter { it.id != f.id }
        }
    }

    fun toggleWatchlist(f: FilmRef) {
        val on = !inWatchlist(f.id)
        mutate(if (on) "Added to watchlist" else "Removed from watchlist", if (on) Icons.Filled.Schedule else Icons.Outlined.Schedule) { d ->
            d.watchlist = if (on) listOf(f) + d.watchlist else d.watchlist.filter { it.id != f.id }
        }
    }

    /// Rating on its own never marks a show watched or touches the watchlist — a stray tap on the
    /// dial shouldn't change your history. Use Watched or Log for that.
    fun rate(f: FilmRef, r: Double?) = mutate { d -> d.ratings = d.ratings.set(f.id, r?.takeIf { it > 0 }) }

    /// Up to eight favourite shows, in one list.
    fun addFavorite(f: FilmRef) {
        if (isFavorite(f.id) || favoritesFull) return
        mutate("Added to favourites", Icons.Filled.Star) { d -> d.replaceFavorites(d.favorites + f) }
    }
    fun removeFavorite(f: FilmRef) = mutate { d -> d.replaceFavorites(d.favorites.filter { it.id != f.id }) }
    fun moveFavorite(from: Int, to: Int) = mutate { d ->
        val list = d.favorites.toMutableList()
        if (from !in list.indices || to !in list.indices) return@mutate
        list.add(to, list.removeAt(from))
        d.replaceFavorites(list)
    }

    fun toggleComfort(f: FilmRef) = setComfort(f, !isComfort(f.id))
    fun setComfort(f: FilmRef, on: Boolean) {
        if (on == isComfort(f.id)) return
        mutate(if (on) "Comfort show — no ratings asked" else "No longer a comfort show", if (on) Icons.Filled.Weekend else Icons.Outlined.Weekend) { d ->
            d.comfort = if (on) d.comfort + f.id else d.comfort - f.id
        }
    }

    fun createList(name: String, note: String = "", ranked: Boolean = false, with: FilmRef? = null): FilmList {
        val l = FilmList(name = name, note = note, ranked = ranked, films = listOfNotNull(with))
        mutate("Created “$name”", Icons.AutoMirrored.Filled.List) { d -> d.lists = listOf(l) + d.lists }
        return l
    }
    fun updateList(l: FilmList) {
        val u = l.copy(updatedAt = System.currentTimeMillis())
        mutate { d -> d.lists = d.lists.map { if (it.id == u.id) u else it } }
    }
    fun deleteList(l: FilmList) = mutate("List deleted", Icons.Filled.Delete, undoable = true) { d -> d.lists = d.lists.filter { it.id != l.id } }
    fun toggle(f: FilmRef, list: FilmList) {
        mutate { d ->
            d.lists = d.lists.map { l ->
                if (l.id != list.id) l
                else l.copy(films = if (l.films.any { it.id == f.id }) l.films.filter { it.id != f.id } else l.films + f, updatedAt = System.currentTimeMillis())
            }
        }
        val added = doc.lists.firstOrNull { it.id == list.id }?.films?.any { it.id == f.id } ?: false
        toast = Toast(if (added) "Added to ${list.name}" else "Removed from ${list.name}", Icons.AutoMirrored.Filled.List)
    }

    // MARK: Episodes

    fun progress(showID: String): ShowProgress? = doc.shows[showID]
    fun isSeen(showID: String, ep: Episode) = doc.shows[showID]?.seen?.containsKey(ep.id) == true
    fun seenCount(showID: String, season: Int) = doc.shows[showID]?.seenCount(season) ?: 0

    /// Shows you've started, most recently watched first. Finished shows drop off.
    val showsInProgress: List<FilmRef>
        get() {
            val done = doc.watched.map { it.id }.toSet()
            return doc.shows.values.filter { it.seen.isNotEmpty() && it.show.id !in done }
                .sortedByDescending { it.seen.values.maxOrNull() ?: 0L }
                .map { it.show }
        }

    fun setSeen(show: FilmRef, eps: List<Episode>, on: Boolean) {
        if (eps.isEmpty()) return
        val text = if (eps.size == 1) "${if (on) "Watched" else "Unwatched"} ${eps[0].code}"
        else if (on) "Marked ${eps.size} episodes watched" else "Unmarked ${eps.size} episodes"
        mutate(text, if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle, undoable = !on) { d ->
            editShow(show, d) { seen ->
                for (e in eps) if (on) seen.putIfAbsent(e.id, System.currentTimeMillis()) else seen.remove(e.id)
            }
            if (on) d.watchlist = d.watchlist.filter { it.id != show.id }
        }
    }

    fun toggleSeen(show: FilmRef, ep: Episode) = setSeen(show, listOf(ep), !isSeen(show.id, ep))

    /// Shows pinned to the top of Home, with the next episode ready to tick off.
    fun toggleCurrentlyWatching(show: FilmRef) {
        val on = !isCurrentlyWatching(show.id)
        mutate(if (on) "Pinned to Currently watching" else "Removed from Currently watching", if (on) Icons.Filled.PushPin else Icons.Outlined.PushPin) { d ->
            d.currentlyWatching = if (on) listOf(show) + d.currentlyWatching else d.currentlyWatching.filter { it.id != show.id }
        }
    }

    /// After the last episode of a show that has ended: it joins your watched shows.
    fun finishShow(show: FilmRef) {
        if (doc.watched.any { it.id == show.id }) return
        mutate { d ->
            d.watched = d.watched + show
            d.watchlist = d.watchlist.filter { it.id != show.id }
            d.currentlyWatching = d.currentlyWatching.filter { it.id != show.id }
        }
    }

    private fun editShow(show: FilmRef, d: LibraryDoc, change: (MutableMap<String, Long>) -> Unit) {
        val p = d.shows[show.id] ?: ShowProgress(show)
        val seen = p.seen.toMutableMap()
        change(seen)
        val updated = p.copy(show = if (p.show.poster == null) show else p.show, seen = seen, updatedAt = System.currentTimeMillis())
        d.shows = if (updated.isEmpty) d.shows - show.id else d.shows + (show.id to updated)
    }

    fun setProfile(p: Profile) = mutate { d -> d.profile = p }

    /// Sample data for the CI screenshots.
    fun loadDemo(d: LibraryDoc) {
        doc = d
        persist()
    }

    /// Episodes in progress ride along with the library. Quiet: no toast, no undo.
    fun storeWatching(sessions: List<WatchSession>) {
        if (sessions == doc.watching) return
        doc = doc.copy(watching = sessions, updatedAt = System.currentTimeMillis())
        persist()
    }

    fun storeTaste(t: TasteProfile) {
        doc = doc.copy(taste = t, updatedAt = System.currentTimeMillis())
        persist()
    }

    fun rememberSearch(q: String) {
        val t = q.trim()
        if (t.isEmpty()) return
        mutate { d -> d.recentSearches = (listOf(t) + d.recentSearches.filter { !it.equals(t, ignoreCase = true) }).take(8) }
    }
    fun clearSearches() = mutate { d -> d.recentSearches = emptyList() }

    /// Fill in a poster (and category) for shows saved without one.
    fun hydrate(f: FilmRef, detail: FilmDetail) {
        val r = detail.ref
        if ((f.poster != null || r.poster == null) && (f.lang != null || r.lang == null)) return
        fun fix(x: FilmRef) = if (x.id == r.id) x.copy(poster = x.poster ?: r.poster, backdrop = x.backdrop ?: r.backdrop, year = x.year ?: r.year, lang = x.lang ?: r.lang) else x
        val d = doc.copy()
        d.entries = d.entries.map { it.copy(film = fix(it.film)) }
        d.watchlist = d.watchlist.map(::fix)
        d.liked = d.liked.map(::fix)
        d.watched = d.watched.map(::fix)
        d.favorites = d.favorites.map(::fix)
        d.currentlyWatching = d.currentlyWatching.map(::fix)
        d.lists = d.lists.map { l -> l.copy(films = l.films.map(::fix)) }
        d.shows[r.id]?.let { d.shows = d.shows + (r.id to it.copy(show = fix(it.show))) }
        doc = d
        persist()
    }

    fun eraseAll() = mutate("Library cleared", Icons.Filled.Delete, undoable = true) { d ->
        val fresh = LibraryDoc(profile = d.profile)
        d.entries = fresh.entries; d.watchlist = fresh.watchlist; d.liked = fresh.liked; d.ratings = fresh.ratings
        d.watched = fresh.watched; d.lists = fresh.lists; d.recentSearches = fresh.recentSearches; d.taste = null
        d.shows = fresh.shows; d.favorites = fresh.favorites; d.currentlyWatching = fresh.currentlyWatching
        d.comfort = fresh.comfort; d.watching = fresh.watching
    }.also { Watching.load(emptyList()) }

    /// A backup file of the whole library.
    fun exportJSON(): String = AppJson.encodeToString(LibraryDoc.serializer(), doc)

    /// Restore a backup made with Export. Undoable.
    fun importJSON(text: String): Boolean {
        val d = runCatching { AppJson.decodeFromString(LibraryDoc.serializer(), text) }.getOrNull() ?: return false
        mutate("Library restored", Icons.Filled.CheckCircle, undoable = true) { cur ->
            cur.entries = d.entries; cur.watchlist = d.watchlist; cur.liked = d.liked; cur.ratings = d.ratings
            cur.watched = d.watched; cur.lists = d.lists; cur.profile = d.profile; cur.recentSearches = d.recentSearches
            cur.taste = d.taste; cur.shows = d.shows; cur.favorites = d.favorites; cur.currentlyWatching = d.currentlyWatching
            cur.comfort = d.comfort; cur.watching = d.watching
        }
        Watching.load(d.watching)
        d.taste?.let { Taste.adopt(it) }
        return true
    }

    // MARK: Persistence

    private fun persist() {
        if (!::file.isInitialized) return
        val snapshot = doc
        writer.execute {
            runCatching {
                val tmp = File(file.parentFile, "library.json.tmp")
                tmp.writeText(AppJson.encodeToString(LibraryDoc.serializer(), snapshot))
                tmp.renameTo(file)
            }
        }
    }
}

private fun Map<String, Double>.set(key: String, value: Double?): Map<String, Double> = if (value == null) this - key else this + (key to value)

/// Small settings that aren't part of the library: how you rate, the token, which tab of each switch is on.
object Prefs {
    private lateinit var p: SharedPreferences

    var ratingStyle by mutableStateOf(RatingStyle.SCORE)
        private set
    var tmdbToken by mutableStateOf("")
        private set
    var homeFilter by mutableStateOf(DramaFilter.ALL)
        private set
    var watchlistFilter by mutableStateOf(DramaFilter.ALL)
        private set
    var librarySection by mutableStateOf("Watchlist")
        private set
    var watchlistSortByTitle by mutableStateOf(false)
        private set
    var deckMode by mutableStateOf(true)
        private set

    fun init(context: Context) {
        p = context.getSharedPreferences("matinee", Context.MODE_PRIVATE)
        ratingStyle = runCatching { RatingStyle.valueOf(p.getString("ratingStyle", "SCORE")!!) }.getOrDefault(RatingStyle.SCORE)
        tmdbToken = p.getString("tmdbToken", "") ?: ""
        homeFilter = runCatching { DramaFilter.valueOf(p.getString("homeFilter", "ALL")!!) }.getOrDefault(DramaFilter.ALL)
        watchlistFilter = runCatching { DramaFilter.valueOf(p.getString("watchlistFilter", "ALL")!!) }.getOrDefault(DramaFilter.ALL)
        librarySection = p.getString("librarySection", "Watchlist") ?: "Watchlist"
        watchlistSortByTitle = p.getBoolean("watchlistSort", false)
        deckMode = p.getBoolean("deckMode", true)
    }

    fun putRatingStyle(v: RatingStyle) { ratingStyle = v; p.edit().putString("ratingStyle", v.name).apply() }
    fun putTmdbToken(v: String) { tmdbToken = v.trim(); p.edit().putString("tmdbToken", tmdbToken).apply() }
    fun putHomeFilter(v: DramaFilter) { homeFilter = v; p.edit().putString("homeFilter", v.name).apply() }
    fun putWatchlistFilter(v: DramaFilter) { watchlistFilter = v; p.edit().putString("watchlistFilter", v.name).apply() }
    fun putLibrarySection(v: String) { librarySection = v; p.edit().putString("librarySection", v).apply() }
    fun putWatchlistSortByTitle(v: Boolean) { watchlistSortByTitle = v; p.edit().putBoolean("watchlistSort", v).apply() }
    fun putDeckMode(v: Boolean) { deckMode = v; p.edit().putBoolean("deckMode", v).apply() }

    fun getBoolean(key: String, def: Boolean) = p.getBoolean(key, def)
    fun putBoolean(key: String, v: Boolean) = p.edit().putBoolean(key, v).apply()
}
