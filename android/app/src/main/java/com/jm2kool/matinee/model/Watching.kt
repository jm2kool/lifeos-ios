package com.jm2kool.matinee.model

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

/// A pause mid-episode: where you stopped, how it felt, and a note to jog your memory.
@Serializable
data class Intermission(
    val id: String = UUID.randomUUID().toString(),
    val at: Double,                         // position, seconds
    val `when`: Long = System.currentTimeMillis(),
    val mood: String,
    val note: String,
)

/// An episode you're partway through.
@Serializable
data class WatchSession(
    val id: String = UUID.randomUUID().toString(),
    val film: FilmRef,
    val runtimeMinutes: Int? = null,
    val runStartedAt: Long? = System.currentTimeMillis(),   // null while on intermission
    val banked: Double = 0.0,                                  // seconds reached before the current run
    val stops: List<Intermission> = emptyList(),
    val started: Long = System.currentTimeMillis(),
    val season: Int? = null,
    val episode: Int? = null,
    val episodeTitle: String? = null,
) {
    val episodeCode: String? get() = if (season != null && episode != null) EpisodeKey.code(season, episode) else null
    /// "Crash Landing on You · S1 E3" for an episode, the show's title otherwise.
    val title: String get() = episodeCode?.let { "${film.title} · $it" } ?: film.title

    val running: Boolean get() = runStartedAt != null
    fun elapsed(now: Long = System.currentTimeMillis()): Double =
        banked + (runStartedAt?.let { max(0.0, (now - it) / 1000.0) } ?: 0.0)
    val runtime: Double? get() = runtimeMinutes?.takeIf { it > 0 }?.let { it * 60.0 }
    fun progress(now: Long = System.currentTimeMillis()): Double? = runtime?.let { min(1.0, elapsed(now) / it) }
    fun isProbablyOver(now: Long = System.currentTimeMillis()): Boolean = runtime?.let { elapsed(now) >= it } ?: false
    val lastStop: Intermission? get() = stops.lastOrNull()
}

object Mood {
    val all = listOf(
        "😍" to "Loving it", "🤯" to "Mind-blown", "😱" to "Tense", "😂" to "Fun",
        "🥲" to "Moved", "🤔" to "Unsure", "😴" to "Slow",
    )
    fun label(e: String): String = all.firstOrNull { it.first == e }?.second ?: ""
}

/// Episodes you're in the middle of. Kept with the library on the phone.
object Watching {
    var sessions by mutableStateOf<List<WatchSession>>(emptyList())
        private set

    fun load(s: List<WatchSession>) { sessions = s }

    /// The session to show in the Now Watching bar: the running one, else the most recent intermission.
    val current: WatchSession?
        get() = sessions.firstOrNull { it.running } ?: sessions.maxByOrNull { it.lastStop?.`when` ?: it.started }
    val paused: List<WatchSession>
        get() = sessions.filter { !it.running }.sortedByDescending { it.lastStop?.`when` ?: it.started }

    fun session(filmID: String): WatchSession? = sessions.firstOrNull { it.film.id == filmID }

    private fun bankRunning(s: MutableList<WatchSession>) {
        for (i in s.indices) if (s[i].running) s[i] = s[i].copy(banked = s[i].elapsed(), runStartedAt = null)
    }

    /// Start an episode. A show has one session at a time, so a different episode replaces the old one.
    fun start(show: FilmRef, ep: Episode, runtime: Int?) = update { s ->
        bankRunning(s)
        val i = s.indexOfFirst { it.film.id == show.id }
        if (i >= 0) {
            if (s[i].season == ep.season && s[i].episode == ep.number) {
                s[i] = s[i].copy(runStartedAt = System.currentTimeMillis()); return@update
            }
            s.removeAt(i)
        }
        s.add(WatchSession(film = show, runtimeMinutes = ep.runtime ?: runtime, season = ep.season, episode = ep.number, episodeTitle = ep.name))
    }

    fun intermission(id: String, position: Double, mood: String, note: String) = update { s ->
        val i = s.indexOfFirst { it.id == id }
        if (i < 0) return@update
        s[i] = s[i].copy(banked = position, runStartedAt = null,
            stops = s[i].stops + Intermission(at = position, mood = mood, note = note.trim()))
    }

    fun resume(id: String) = update { s ->
        bankRunning(s)
        val i = s.indexOfFirst { it.id == id }
        if (i >= 0) s[i] = s[i].copy(runStartedAt = System.currentTimeMillis())
    }

    fun end(id: String): WatchSession? {
        val s = sessions.firstOrNull { it.id == id }
        update { list -> list.removeAll { it.id == id } }
        return s
    }

    private fun update(change: (MutableList<WatchSession>) -> Unit) {
        val s = sessions.toMutableList()
        change(s)
        sessions = s
        Library.storeWatching(s)
    }
}
