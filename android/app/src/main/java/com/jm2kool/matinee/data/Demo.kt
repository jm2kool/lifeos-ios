package com.jm2kool.matinee.data

import android.content.Intent
import com.jm2kool.matinee.model.Category
import com.jm2kool.matinee.model.EpisodeKey
import com.jm2kool.matinee.model.FilmList
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Intermission
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.LibraryDoc
import com.jm2kool.matinee.model.LogEntry
import com.jm2kool.matinee.model.Profile
import com.jm2kool.matinee.model.ShowProgress
import com.jm2kool.matinee.model.TasteProfile
import com.jm2kool.matinee.model.WatchSession
import com.jm2kool.matinee.model.Watching
import com.jm2kool.matinee.ui.AppTab
import com.jm2kool.matinee.ui.CollectionKind
import com.jm2kool.matinee.ui.CollectionRoute
import com.jm2kool.matinee.ui.ListRoute
import com.jm2kool.matinee.ui.Router
import com.jm2kool.matinee.ui.SheetRoute
import kotlinx.coroutines.delay

/// Hooks used by the CI emulator run to capture screenshots, with sample data from TMDB's popular shelves.
/// Launch with `--ez preview true` and, optionally, `--es tab diary`, `--es open show|list|forYou`,
/// `--es sheet log|quiz|shake`, `--ei scroll 1400`.
object Demo {
    var scrollTo: Int? = null

    suspend fun run(intent: Intent) {
        if (!intent.getBooleanExtra("preview", false)) return
        Router.showSplash = intent.getBooleanExtra("splash", false)
        seed()
        intent.getStringExtra("tab")?.let { t -> AppTab.entries.firstOrNull { it.name.equals(t, true) }?.let { Router.tab = it } }
        scrollTo = intent.getIntExtra("scroll", 0).takeIf { it > 0 }
        delay(800)
        when (intent.getStringExtra("open")) {
            "show" -> (Library.currentlyWatching.firstOrNull() ?: Library.watchedFilms.firstOrNull())?.let { Router.open(it) }
            "show2" -> Library.watchedFilms.getOrNull(1)?.let { Router.open(it) }
            "list" -> Library.doc.lists.firstOrNull()?.let { Router.tab = AppTab.LIBRARY; Router.push(ListRoute(it.id)) }
            "watchlist" -> Router.push(CollectionRoute(CollectionKind.Watchlist))
        }
        when (intent.getStringExtra("sheet")) {
            "log" -> Library.watchedFilms.firstOrNull()?.let { delay(1200); Router.sheet = SheetRoute.Log(it, null) }
            "quiz" -> { delay(600); Taste.showQuiz = true }
            "shake" -> { delay(1200); Router.pickRandom() }
            "settings" -> { delay(600); Router.sheet = SheetRoute.Settings }
        }
    }

    private suspend fun seed() {
        if (!Catalog.hasToken) return
        val pools = Category.entries.map { c -> runCatching { Catalog.shelf(Shelf(ShelfKind.POPULAR, c)) }.getOrDefault(emptyList()) }
        val top = runCatching { Catalog.shelf(Shelf(ShelfKind.TOP, null)) }.getOrDefault(emptyList())
        if (pools.all { it.isEmpty() }) return
        // Take turns between the four, so every category has something.
        val mixed = TMDB.interleave(pools)
        val watched = (top.take(6) + mixed.drop(8).take(4)).distinctBy { it.id }
        val day = 86_400_000L
        val now = System.currentTimeMillis()
        val ratings = listOf(97.0, 91.0, 88.0, 95.0, 72.0, 84.0, 90.0, 66.0, 99.0, 80.0)
        val d = LibraryDoc()
        d.entries = watched.mapIndexed { i, f ->
            LogEntry(film = f, watchedOn = now - (i * 4 + 1) * day, rating = ratings[i % ratings.size], liked = ratings[i % ratings.size] >= 88,
                rewatch = i == 3, review = if (i == 0) "Cried at the finale, then started it again the next morning." else "",
                tags = if (i % 3 == 0) listOf("with mum") else emptyList())
        }
        d.ratings = d.entries.associate { it.film.id to it.rating!! }
        d.liked = d.entries.filter { it.liked }.map { it.film }
        // A show partway through: three episodes in.
        val current = mixed.first()
        val seen = (1..3).associate { EpisodeKey.make(1, it) to now - (10 - it) * day }
        d.shows = mapOf(current.id to ShowProgress(current, seen))
        d.currentlyWatching = listOf(current)
        d.watchlist = mixed.drop(1).take(7)
        d.replaceFavorites(listOf(watched.getOrNull(0), current, watched.getOrNull(1), watched.getOrNull(3), watched.getOrNull(8)).filterNotNull())
        d.lists = listOf(FilmList(name = "Weekend binge", note = "Short ones we can finish in a weekend.", ranked = true, films = (watched.take(2) + mixed.drop(1).take(3))))
        d.profile = Profile(name = "Alex Rivera", bio = "Tissues ready for every finale.")
        d.taste = TasteProfile(
            scores = mapOf("Romance" to 6.0, "Comedy" to 4.4, "Melodrama" to 3.0, "Mystery" to 1.4, "Action" to -1.2),
            likedYears = listOf(2016, 2019, 2020, 2023, 2021), seen = 20,
        ).let { it.copy(persona = Taste.persona(it)) }
        val session = WatchSession(film = current, runtimeMinutes = 70, runStartedAt = null, banked = 41 * 60.0, season = 1, episode = 4, episodeTitle = "Episode 4",
            stops = listOf(Intermission(at = 41 * 60.0, `when` = now - 2 * day, mood = "😍", note = "right after the rooftop confession")))
        d.watching = listOf(session)
        Library.loadDemo(d)
        Watching.load(d.watching)
        Taste.adopt(d.taste!!)
    }
}
