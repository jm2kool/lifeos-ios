package com.jm2kool.matinee.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.Shelf
import com.jm2kool.matinee.data.ShelfKind
import com.jm2kool.matinee.data.Taste
import com.jm2kool.matinee.model.Category
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.RatingStyle
import com.jm2kool.matinee.model.Stars
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import kotlinx.coroutines.delay

@Composable
fun SearchView() {
    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<List<FilmRef>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(query) {
        val q = query
        if (q.isBlank()) { results = emptyList(); return@LaunchedEffect }
        delay(350)
        loading = true
        runCatching { Catalog.search(q) }.onSuccess { results = it; error = null }.onFailure { error = it.message }
        loading = false
    }
    AmbientScreen(results.take(3)) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding()) {
            LargeTitle("Search")
            SearchField(query, { query = it }, "K-dramas, C-dramas, Thai and Japanese dramas", Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
                Library.rememberSearch(query)
            }
            Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                when {
                    !Catalog.hasToken -> TMDBConnectCard()
                    query.isBlank() -> {
                        val recent = Library.doc.recentSearches
                        if (recent.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            SectionHeader("Recent") { TextLink("Clear") { Library.clearSearches() } }
                            Column {
                                for (q in recent) Row(Modifier.fillMaxWidth().clickable { query = q }.padding(vertical = 12.dp, horizontal = 20.dp),
                                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Icon(Icons.Filled.History, null, tint = Theme.dim, modifier = Modifier.size(20.dp))
                                    Text(q, style = Type.body, color = Color.White, modifier = Modifier.weight(1f))
                                    Icon(Icons.AutoMirrored.Filled.CallMade, null, tint = Theme.dim, modifier = Modifier.size(14.dp))
                                }
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionHeader("Categories")
                            TileGrid(Category.entries.map { it.flag + "  " + it.plural to it.label }) { i ->
                                val c = Category.entries[i]
                                Router.push(CollectionRoute(CollectionKind.ShelfOf(Shelf(ShelfKind.POPULAR, c), "Popular ${c.plural}")))
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionHeader("Genres")
                            TileGrid(Catalog.genreNames.map { it to it }) { i -> Router.push(GenreRoute(Catalog.genreNames[i])) }
                        }
                    }
                    loading && results.isEmpty() -> Box(Modifier.fillMaxWidth().padding(top = 60.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                    }
                    error != null && results.isEmpty() -> EmptyState(Icons.Filled.WifiOff, "Search failed", error ?: "", Modifier.padding(top = 40.dp))
                    results.isEmpty() -> EmptyState(Icons.Filled.Search, "Nothing found",
                        "Try a different spelling or the original title. Only K-dramas, C-dramas, Thai and Japanese dramas show up here.", Modifier.padding(top = 40.dp))
                    else -> Column { for (f in results) SearchRow(f) }
                }
            }
            BottomSpace()
        }
    }
}

@Composable
private fun TileGrid(items: List<Pair<String, String>>, onClick: (Int) -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in items.withIndex().chunked(2)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((i, item) in row) Box(Modifier.weight(1f).clickable { onClick(i) }) { GenreTile(item.first, item.second) }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun SearchRow(film: FilmRef) {
    val saved = Library.inWatchlist(film.id)
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        FilmMenuBox(film, Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                PosterView(film, width = 54.dp, corner = 6.dp)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(film.title, style = Type.body.semibold(), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        film.category?.let { c ->
                            Text(c.short, style = Type.caption2.heavy(), color = Theme.list,
                                modifier = Modifier.background(Theme.list.copy(alpha = 0.25f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 1.dp))
                        }
                        Text(film.yearText, style = Type.subheadline, color = Theme.dim)
                        if (Library.isWatched(film.id)) Icon(Icons.Filled.Visibility, null, tint = Theme.watch, modifier = Modifier.size(15.dp))
                        SmallRating(Library.rating(film.id))
                    }
                }
            }
        }
        Box(Modifier.size(44.dp).clip(CircleShape).background(Theme.chip).clickable {
            Library.toggleWatchlist(film); if (saved) Haptics.light() else Haptics.medium()
        }, contentAlignment = Alignment.Center) {
            Icon(if (saved) Icons.Filled.Schedule else Icons.Filled.Add, if (saved) "Remove from watchlist" else "Add to watchlist",
                tint = if (saved) Theme.list else Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
fun GenreTile(name: String, seed: String = name) {
    val hue = (seed.fold(0) { acc, c -> (acc * 31 + c.code) % 997 }) / 997f * 360f
    Box(Modifier.fillMaxWidth().height(84.dp).clip(RoundedCornerShape(18.dp))
        .background(Brush.linearGradient(listOf(Color.hsv(hue, 0.75f, 0.55f), Color.hsv(hue, 0.9f, 0.18f)))),
        contentAlignment = Alignment.BottomStart) {
        Text(name, style = Type.headline, color = Color.White, modifier = Modifier.padding(14.dp))
    }
}

/// Search-and-log in one place, opened from the Diary's + button.
@Composable
fun QuickLogSheet() {
    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<List<FilmRef>>(emptyList()) }
    LaunchedEffect(query) {
        if (query.isBlank()) { results = emptyList(); return@LaunchedEffect }
        delay(300)
        runCatching { Catalog.search(query) }.onSuccess { results = it }
    }
    val pool = if (query.isBlank()) (Library.currentlyWatching + Library.showsInProgress + Library.doc.watchlist + Library.watchedFilms).distinctBy { it.id }.take(20) else results
    Column(Modifier.fillMaxSize().background(Theme.bg).imePadding()) {
        SheetBar("What did you watch?", leading = { CloseButton() })
        SearchField(query, { query = it }, "Search shows", Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 8.dp)) {
            if (query.isBlank() && pool.isNotEmpty()) Text("From what you're watching and your watchlist", style = Type.caption.semibold(), color = Theme.dim,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
            for (f in pool) {
                Row(Modifier.fillMaxWidth().clickable { Router.sheet = SheetRoute.Log(f, null) }.padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    PosterView(f, width = 40.dp, corner = 4.dp)
                    Column(Modifier.weight(1f)) {
                        Text(f.title, style = Type.body.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOfNotNull(f.yearText.ifEmpty { null }, f.category?.label).joinToString(" · "), style = Type.subheadline, color = Theme.dim)
                    }
                    Icon(Icons.Filled.AddCircle, null, tint = Theme.accent, modifier = Modifier.size(28.dp))
                }
            }
        }
    }
}

/// Dramas in one genre, in the category picked on Home (or all four).
@Composable
fun GenreView(genre: String) {
    var films by remember { mutableStateOf<List<FilmRef>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    val category = Prefs.homeFilter.category
    LaunchedEffect(genre, category) {
        val g = Catalog.genreNamed(genre)
        films = if (g == null) emptyList() else runCatching { Catalog.genre(g, category) }.getOrDefault(emptyList())
        failed = films.isEmpty()
    }
    AmbientScreen(films.take(3)) {
        Column(Modifier.fillMaxSize()) {
            TopBar(listOfNotNull(genre, category?.plural).joinToString(" · "))
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                when {
                    films.isNotEmpty() -> PosterGrid(films, columns = 3, modifier = Modifier.padding(16.dp))
                    failed -> EmptyState(Icons.Filled.LiveTv, "Nothing here yet", "Couldn't load $genre dramas.", Modifier.padding(top = 60.dp))
                    else -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                    }
                }
                BottomSpace()
            }
        }
    }
}

@Composable
fun CollectionView(kind: CollectionKind) {
    var remote by remember { mutableStateOf<List<FilmRef>?>(null) }
    LaunchedEffect(kind) { if (kind is CollectionKind.ShelfOf) remote = runCatching { Catalog.shelf(kind.shelf) }.getOrDefault(emptyList()) }
    val media = Prefs.homeFilter
    val title = when (kind) {
        is CollectionKind.ShelfOf -> kind.title
        CollectionKind.Watched -> "Shows"
        CollectionKind.Liked -> "Likes"
        CollectionKind.Watchlist -> "Watchlist"
        is CollectionKind.Tag -> "#${kind.tag}"
        is CollectionKind.Rated -> if (Prefs.ratingStyle == RatingStyle.STARS) Stars.text((kind.band + 1) / 2.0) else "Scored ${kind.band * 10 + 1}–${kind.band * 10 + 10}"
        CollectionKind.ForYou -> media.category?.let { "${it.plural} you'd like" } ?: "Picked for you"
        CollectionKind.Shows -> "Continue watching"
    }
    val films: List<FilmRef> = when (kind) {
        is CollectionKind.ShelfOf -> remote ?: emptyList()
        CollectionKind.Watched -> Library.watchedFilms
        CollectionKind.Liked -> Library.doc.liked.asReversed()
        CollectionKind.Watchlist -> Library.doc.watchlist
        is CollectionKind.Tag -> Library.entries.filter { kind.tag in it.tags }.map { it.film }.distinctBy { it.id }
        is CollectionKind.Rated -> Library.watchedFilms.filter { f -> Library.rating(f.id)?.let { Library.band(it) == kind.band } == true }
        CollectionKind.ForYou -> Taste.picks.filter(media::includes)
        CollectionKind.Shows -> Library.showsInProgress + Library.watchedFilms
    }
    val action = when (kind) {
        CollectionKind.Watchlist -> DeckAction.TONIGHT
        CollectionKind.Watched, CollectionKind.Liked, is CollectionKind.Rated, is CollectionKind.Tag, CollectionKind.Shows -> DeckAction.LIKE
        else -> DeckAction.WATCHLIST
    }
    val deck = Prefs.deckMode && films.isNotEmpty()
    AmbientScreen(films.take(3)) {
        Column(Modifier.fillMaxSize()) {
            TopBar(title) { DeckToggle() }
            if (deck) FilmDeckScreen(films, action)
            else Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                when {
                    films.isEmpty() && kind is CollectionKind.ShelfOf && remote == null -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                    }
                    films.isEmpty() -> EmptyState(Icons.Filled.LiveTv, "Nothing here yet", "Shows you add will show up here.", Modifier.padding(top = 60.dp))
                    else -> PosterGrid(films, modifier = Modifier.padding(16.dp))
                }
                BottomSpace()
            }
        }
    }
}
