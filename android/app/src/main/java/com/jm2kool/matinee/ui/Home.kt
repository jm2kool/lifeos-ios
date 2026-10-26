package com.jm2kool.matinee.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.FilmArt
import com.jm2kool.matinee.data.Shelf
import com.jm2kool.matinee.data.ShelfKind
import com.jm2kool.matinee.data.Taste
import com.jm2kool.matinee.model.Category
import com.jm2kool.matinee.model.DramaFilter
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/// The rows Home shows for a filter: each category's popular dramas side by side, or one category in depth.
fun homeShelves(filter: DramaFilter): List<Pair<Shelf, String>> {
    val c = filter.category
    return if (c == null) {
        Category.entries.map { Shelf(ShelfKind.POPULAR, it) to "Popular ${it.plural}" } +
            listOf(Shelf(ShelfKind.NEW, null) to ShelfKind.NEW.title, Shelf(ShelfKind.TOP, null) to ShelfKind.TOP.title)
    } else {
        ShelfKind.entries.map { Shelf(it, c) to it.title }
    }
}

@Composable
fun HomeView() {
    val media = Prefs.homeFilter
    val shelves = remember { mutableStateMapOf<String, List<FilmRef>>() }
    var failed by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableStateOf(0) }
    val connected = Catalog.hasToken
    val token = Prefs.tmdbToken
    val rows = homeShelves(media)

    LaunchedEffect(token, media, reload) {
        if (!connected) return@LaunchedEffect
        failed = false; errorText = null
        coroutineScope {
            rows.map { (s, _) ->
                async {
                    Catalog.cachedShelf(s)?.let { shelves[s.key] = it; return@async }
                    runCatching { Catalog.shelf(s) }.onSuccess { shelves[s.key] = it }.onFailure { errorText = it.message }
                }
            }.awaitAll()
        }
        if (rows.all { shelves[it.first.key].isNullOrEmpty() }) failed = true
    }

    /// What's popular, in the kind you've picked: one category, or all four taking turns.
    val hero: List<FilmRef> = remember(media, shelves.toMap()) {
        if (media.category != null) (shelves[Shelf(ShelfKind.POPULAR, media.category).key] ?: emptyList()).filter { it.backdrop != null }.take(8)
        else {
            val lists = Category.entries.map { c -> (shelves[Shelf(ShelfKind.POPULAR, c).key] ?: emptyList()).filter { it.backdrop != null } }
            val mixed = ArrayList<FilmRef>()
            for (i in 0 until 2) for (l in lists) l.getOrNull(i)?.let { mixed.add(it) }
            mixed.take(8)
        }
    }
    val picks = Taste.picks.filter(media::includes)
    val watchlist = Library.doc.watchlist.filter(media::includes)
    /// Shows you're partway through that aren't already pinned under Currently watching.
    val continueWatching = Library.showsInProgress.filter { !Library.isCurrentlyWatching(it.id) && media.includes(it) }
    var heroPage by rememberSaveable { mutableStateOf(0) }
    /// The page glow follows the hero show on screen, mixed with what's next for you.
    val glowFilms = listOfNotNull(hero.getOrNull(heroPage), picks.firstOrNull(), watchlist.firstOrNull(),
        shelves[rows.last().first.key]?.firstOrNull())

    AmbientScreen(glowFilms, intensity = 0.5f) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(34.dp)) {
            if (connected) HeroSection(hero, failed, heroPage) { heroPage = it } else {
                Column(Modifier.statusBarsPadding().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(34.dp)) {
                    HomeHeader()
                    TMDBConnectCard()
                }
            }
            val pinned = Library.currentlyWatching.filter(media::includes)
            if (pinned.isNotEmpty()) CurrentlyWatchingSection(pinned)
            IntermissionShelf(media)
            if (continueWatching.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
                    SectionHeader("Continue watching", "Shows you're partway through") { TextLink("See all") { Router.push(CollectionRoute(CollectionKind.Shows)) } }
                    ShowProgressRow(continueWatching)
                }
            }
            if (connected) ForYou(media, picks)
            if (watchlist.isNotEmpty()) {
                Column {
                    SectionHeader("Up next", "From your watchlist") { TextLink("See all") { Router.push(CollectionRoute(CollectionKind.Watchlist)) } }
                    PosterRow(watchlist.take(15))
                }
            }
            for ((s, title) in rows) {
                val films = shelves[s.key]
                if (!films.isNullOrEmpty()) {
                    Column {
                        SectionHeader(title) { TextLink("See all") { Router.push(CollectionRoute(CollectionKind.ShelfOf(s, title))) } }
                        // The hero already shows the first few popular shows.
                        PosterRow(if (s.kind == ShelfKind.POPULAR && media.category != null) films.drop(minOf(3, films.size)) else films)
                    }
                }
            }
            if (connected && failed && shelves.isEmpty()) {
                Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(Theme.card, RoundedCornerShape(22.dp)).padding(18.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Icon(Icons.Filled.WifiOff, null, tint = Theme.accent, modifier = Modifier.size(28.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Couldn't load shows", style = Type.headline, color = Color.White)
                        Text(errorText ?: "Check your connection and try again.", style = Type.subheadline, color = Theme.dim)
                        PillButton("Try again", size = ControlSize.SMALL, modifier = Modifier.padding(top = 6.dp)) { reload++ }
                    }
                }
            }
            if (connected) Genres()
            val recent = remember(Library.doc.entries, media) {
                Library.entries.map { it.film }.filter(media::includes).distinctBy { it.id }.take(12)
            }
            if (recent.isNotEmpty()) {
                Column {
                    SectionHeader("Your recent watches") { TextLink("Diary") { Router.select(AppTab.DIARY) } }
                    PosterRow(recent, width = 96.dp)
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

/// Picked for you: grown from your favourites first, then your best-rated shows, your watchlist,
/// and the ones you rated lower (plus anything you loved in the swipe quiz).
@Composable
private fun ForYou(media: DramaFilter, picks: List<FilmRef>) {
    val d = Library.doc
    val hasSeeds = d.favorites.isNotEmpty() || d.watchlist.isNotEmpty() || d.ratings.isNotEmpty()
    val persona = Taste.profile.persona
    if (persona != null || hasSeeds) {
        val sig = Taste.signature()
        LaunchedEffect(sig) {
            // Wait for a burst of rating or saving to settle before asking TMDB again.
            delay(1000)
            runCatching { Taste.refreshPicks() }
        }
        val title = media.category?.let { "${it.plural} you'd like" } ?: "Picked for you"
        Column {
            SectionHeader(title, persona?.let { "For ${it.name} ${it.emoji}" } ?: "From your favourites, ratings and watchlist") {
                if (picks.isNotEmpty()) TextLink("Swipe") { Router.push(CollectionRoute(CollectionKind.ForYou)) }
            }
            when {
                picks.isEmpty() && (Taste.loadingPicks || !Taste.picksReady) ->
                    Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp)) }
                picks.isEmpty() -> Text("Rate or save a few shows and picks will show up here.", style = Type.subheadline, color = Theme.dim,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))
                else -> PosterRow(picks, width = 124.dp)
            }
        }
    } else {
        Row(
            Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(24.dp)).panel(RoundedCornerShape(24.dp))
                .clickable { Taste.showQuiz = true }.padding(18.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("🎭", style = Type.largeTitle)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Find your drama character", style = Type.headline, color = Color.White)
                Text("Swipe through 20 dramas and get recommendations made for you.", style = Type.subheadline, color = Theme.dim)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Theme.dim)
        }
    }
}

/// The greeting, the drama switch and your avatar, all on one line.
@Composable
private fun HomeHeader(modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE d MMM", Locale.getDefault())).uppercase(),
                style = Type.caption2.semibold().tracking(1f), color = Color.White.copy(alpha = 0.7f), maxLines = 1)
            Text(greetingText(), style = Type.title3.heavy(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        DramaFilterBar(Prefs.homeFilter, compact = true) { Prefs.putHomeFilter(it) }
        Box(Modifier.clip(CircleShape).clickable { Router.sheet = SheetRoute.Settings }) { Avatar(Library.doc.profile, 36.dp) }
    }
}

private fun greetingText(): String {
    val h = LocalTime.now().hour
    val part = if (h < 12) "Morning" else if (h < 17) "Afternoon" else "Evening"
    val first = Library.doc.profile.name.split(" ").firstOrNull { it.isNotBlank() }
    return first?.let { "$part, $it" } ?: "Good ${part.lowercase()}"
}

/// Full-bleed, edge-to-edge hero: textless backdrop, the show's logo, and two small buttons.
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HeroSection(hero: List<FilmRef>, failed: Boolean, page: Int, onPage: (Int) -> Unit) {
    val height = (LocalConfiguration.current.screenHeightDp * 0.72f).dp
    val pager = rememberPagerState(initialPage = page.coerceIn(0, maxOf(0, hero.size - 1))) { hero.size }
    val scope = rememberCoroutineScope()
    LaunchedEffect(pager.currentPage) { onPage(pager.currentPage) }
    LaunchedEffect(hero.map { it.id }) {
        if (pager.currentPage >= hero.size && hero.isNotEmpty()) pager.scrollToPage(0)
        // Gently auto-advance, like a cinema lobby screen.
        while (hero.size > 1) {
            delay(7000)
            scope.launch { pager.animateScrollToPage((pager.currentPage + 1) % hero.size) }
        }
    }
    Box(Modifier.fillMaxWidth().height(height)) {
        if (hero.isEmpty()) {
            if (!failed) CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp).align(Alignment.Center))
        } else {
            HorizontalPager(pager, Modifier.fillMaxSize(), key = { hero[it].id }) { i -> HeroPage(hero[i]) }
        }
        HomeHeader(Modifier.statusBarsPadding().padding(top = 6.dp).softShadow(12.dp, alpha = 0.0f))
        if (hero.size > 1) {
            Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (i in hero.indices) {
                    val on = i == pager.currentPage
                    val w by animateDpAsState(if (on) 16.dp else 6.dp, label = "dot")
                    Box(Modifier.width(w).height(6.dp).clip(CircleShape).background(if (on) Color.White else Color.White.copy(alpha = 0.3f)))
                }
            }
        }
    }
}

@Composable
private fun HeroPage(film: FilmRef) {
    var art by remember(film.id) { mutableStateOf<FilmArt?>(null) }
    var artLoaded by remember(film.id) { mutableStateOf(false) }
    LaunchedEffect(film.id) { art = Catalog.art(film.id); artLoaded = true }
    val saved = Library.inWatchlist(film.id)
    Box(Modifier.fillMaxSize()) {
        RemoteImage(
            art?.backdrop ?: film.backdrop ?: film.poster,
            Modifier.fillMaxSize()
                .clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { Router.open(film) }
                // Dissolve the bottom into the glowing page instead of a hard black edge.
                .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                .drawWithContent {
                    drawContent()
                    // Darken only behind the status bar and greeting…
                    drawRect(Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.5f), 0.26f to Color.Transparent))
                    drawRect(Brush.verticalGradient(0f to Color.White, 0.42f to Color.White, 0.68f to Color.White.copy(alpha = 0.55f),
                        0.88f to Color.White.copy(alpha = 0.15f), 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                },
        )
        Column(Modifier.align(Alignment.BottomCenter).padding(horizontal = 24.dp).padding(bottom = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TitleArt(film.title, art?.logo, aspect = art?.logoAspect ?: 3.0, maxWidth = 260.dp, maxHeight = 96.dp, fontSize = 34f, ready = artLoaded)
            Text(listOfNotNull("Trending now", film.category?.label, film.yearText.ifEmpty { null }).joinToString(" · ").uppercase(),
                style = Type.caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold).tracking(1.2f),
                color = Color.White.copy(alpha = 0.8f))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Chip(prominent = true, onClick = { Router.sheet = SheetRoute.Log(film, null) }) { Label("Log", Icons.Filled.Add) }
                Chip(onClick = { Library.toggleWatchlist(film) }) { Label(if (saved) "Saved" else "Watchlist", if (saved) Icons.Filled.Check else Icons.Filled.Schedule) }
            }
        }
    }
}

@Composable
private fun Genres() {
    val all = Catalog.genreNames
    val half = (all.size + 1) / 2
    val rows = listOf(all.take(half), all.drop(half))
    Column {
        SectionHeader("Browse by genre", Prefs.homeFilter.category?.plural)
        Column(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (r in rows) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (g in r) PillButton(g) { Router.push(GenreRoute(g)) }
            }
        }
    }
}

/// Shown until a TMDB token is added — the one bit of setup Matinee needs.
@Composable
fun TMDBConnectCard() {
    var draft by rememberSaveable { mutableStateOf("") }
    val ctx = LocalContext.current
    Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().panel(RoundedCornerShape(28.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MatineeMark(size = 44.dp)
            Text("Connect TMDB", style = Type.title2, color = Color.White)
        }
        Text("Matinee gets shows, posters and cast from TMDB. It's free: make an account, open Settings → API, and copy the API Read Access Token.",
            style = Type.subheadline, color = Color.White.copy(alpha = 0.8f))
        PillButton("Get a free token", Icons.Filled.NorthEast, size = ControlSize.LARGE, fill = true) {
            ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.themoviedb.org/settings/api")))
        }
        BasicTextField(
            draft, { draft = it }, maxLines = 3,
            textStyle = Type.footnote.copy(color = Color.White, fontFamily = FontFamily.Monospace),
            cursorBrush = SolidColor(Theme.accent),
            modifier = Modifier.fillMaxWidth().background(Theme.card, RoundedCornerShape(16.dp)).padding(14.dp),
            decorationBox = { inner -> if (draft.isEmpty()) Text("Paste your token", style = Type.footnote, color = Theme.dim); inner() },
        )
        PillButton("Connect", prominent = true, size = ControlSize.LARGE, fill = true, enabled = draft.trim().length >= 20) {
            Catalog.setToken(draft); Haptics.success()
        }
    }
}
