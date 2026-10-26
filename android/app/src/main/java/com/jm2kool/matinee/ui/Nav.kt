package com.jm2kool.matinee.ui

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import com.jm2kool.matinee.data.Shelf
import com.jm2kool.matinee.model.DramaFilter
import com.jm2kool.matinee.model.Episode
import com.jm2kool.matinee.model.FilmList
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.LogEntry
import com.jm2kool.matinee.model.Toast

enum class AppTab { HOME, DIARY, LIBRARY, PROFILE, SEARCH }

sealed interface Route { val key: String }
data class ShowRoute(val film: FilmRef) : Route { override val key get() = "show-${film.id}" }
data class ListRoute(val id: String) : Route { override val key get() = "list-$id" }
data class GenreRoute(val name: String) : Route { override val key get() = "genre-$name" }
data class CollectionRoute(val kind: CollectionKind) : Route { override val key get() = "collection-$kind" }

sealed interface CollectionKind {
    data class ShelfOf(val shelf: Shelf, val title: String) : CollectionKind
    data object Watched : CollectionKind
    data object Liked : CollectionKind
    data object Watchlist : CollectionKind
    data class Tag(val tag: String) : CollectionKind
    data class Rated(val band: Int) : CollectionKind
    data object ForYou : CollectionKind
    data object Shows : CollectionKind
}

sealed interface SheetRoute {
    data class Log(val film: FilmRef, val existing: LogEntry?) : SheetRoute
    data class AddToList(val film: FilmRef) : SheetRoute
    data class NewList(val film: FilmRef?) : SheetRoute
    data class EditList(val list: FilmList) : SheetRoute
    data object EditFavorites : SheetRoute
    data object EditProfile : SheetRoute
    data object Settings : SheetRoute
    data object QuickLog : SheetRoute
    data class IntermissionOf(val sessionID: String) : SheetRoute
    data class EpisodeOf(val show: FilmRef, val episode: Episode) : SheetRoute
    /// The whole show is finished: rate it.
    data class Wrap(val show: FilmRef) : SheetRoute
}

object Router {
    var tab by mutableStateOf(AppTab.HOME)
    val stacks: Map<AppTab, SnapshotStateList<Route>> = AppTab.entries.associateWith { mutableStateListOf() }
    var sheet by mutableStateOf<SheetRoute?>(null)
    var trailer by mutableStateOf<Pair<String, String>?>(null)    // YouTube key, title
    var showSplash by mutableStateOf(true)

    /// The swipe deck of random watchlist picks, opened by shaking the phone, Random pick, or double-tapping Library.
    /// null while it's closed.
    var randomDeck by mutableStateOf<List<FilmRef>?>(null)
    /// Changes with every fresh shuffle, so the deck starts again from its first card.
    var randomDeckID by mutableIntStateOf(0)
    /// Which category the deck deals from.
    var randomKind by mutableStateOf(DramaFilter.ALL)
    var randomPickOpening = false
    private var lastLibraryTap = 0L

    val stack: SnapshotStateList<Route> get() = stacks.getValue(tab)

    /// Open the deck (or reshuffle it if it's already open).
    fun pickRandom(kind: DramaFilter? = null) {
        if (randomPickOpening) return
        val list = Library.doc.watchlist
        if (list.isEmpty()) {
            Library.toast = Toast("Add shows to your watchlist first", Icons.Filled.Schedule)
            return
        }
        if (kind != null) randomKind = kind
        else if (randomDeck == null) randomKind = DramaFilter.ALL
        deal()
    }

    /// Shuffle the watchlist into a fresh deck of the chosen category.
    fun deal() {
        randomDeckID++
        Haptics.success()
        randomDeck = Library.doc.watchlist.filter(randomKind::includes).shuffled()
    }

    fun closeRandom() {
        randomDeck = null
        randomPickOpening = false
    }

    /// Tab selection that notices a quick double tap on Library, and pops to the root on a second tap.
    fun select(t: AppTab) {
        if (t == AppTab.LIBRARY) {
            val now = System.currentTimeMillis()
            if (now - lastLibraryTap < 450) {
                lastLibraryTap = 0
                pickRandom()
            } else lastLibraryTap = now
        }
        if (t == tab && stack.isNotEmpty()) stack.clear()
        tab = t
    }

    fun open(f: FilmRef) = push(ShowRoute(f))
    fun push(r: Route) { if (stack.lastOrNull()?.key != r.key) stack.add(r) }
    fun pop(): Boolean = if (stack.isNotEmpty()) { stack.removeAt(stack.lastIndex); true } else false
}

/// Taps and ticks under the thumb, like UIKit's feedback generators.
object Haptics {
    var view: View? = null
    fun light() { view?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
    fun selection() { view?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
    fun medium() { view?.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY) }
    fun heavy() { view?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) }
    fun success() { view?.performHapticFeedback(HapticFeedbackConstants.CONFIRM) }
}
