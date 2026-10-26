package com.jm2kool.matinee.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.CheckCircleOutline
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.Palette
import com.jm2kool.matinee.data.PosterPalette
import com.jm2kool.matinee.model.Dates
import com.jm2kool.matinee.model.Episode
import com.jm2kool.matinee.model.EpisodeKey
import com.jm2kool.matinee.model.FilmDetail
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.SeasonInfo
import com.jm2kool.matinee.model.Watching
import com.jm2kool.matinee.model.filmClock
import com.jm2kool.matinee.ui.Type.bold
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

// MARK: - Seasons and episodes on a show's page

/// Season tabs and the episode list with a tick for each one you've seen.
/// Finishing the whole show brings up the wrap-up, where you rate it.
@Composable
fun SeasonsSection(show: FilmRef, detail: FilmDetail, surface: Color = Theme.card, accent: Color = Theme.accent) {
    /// The regular seasons in order, then the specials.
    val seasons = detail.regularSeasons + detail.seasons.filter { it.number == 0 && it.episodeCount > 0 }
    if (seasons.isEmpty()) return
    var selected by rememberSaveable(show.id) { mutableStateOf<Int?>(null) }
    val episodes = remember(show.id) { mutableStateMapOf<Int, List<Episode>>() }
    val failed = remember(show.id) { mutableStateMapOf<Int, Boolean>() }
    var pendingWrap by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    /// Where you're up to: the first season you haven't finished.
    val current = selected ?: detail.regularSeasons.firstOrNull { Library.seenCount(show.id, it.number) < it.episodeCount }?.number
        ?: detail.regularSeasons.lastOrNull()?.number ?: seasons.first().number
    val totalSeen = detail.regularSeasons.sumOf { minOf(it.episodeCount, Library.seenCount(show.id, it.number)) }
    val totalEpisodes = detail.regularSeasons.sumOf { it.episodeCount }

    suspend fun load(season: Int) {
        if (episodes[season] != null) return
        Catalog.cachedSeason(show.id, season)?.let { episodes[season] = it; return }
        runCatching { Catalog.season(show.id, season) }.onSuccess { episodes[season] = it }.onFailure { failed[season] = true }
    }

    LaunchedEffect(current) {
        // Pin the season you're on, so finishing it doesn't jump the page to the next one mid-celebration.
        if (selected == null) selected = current
        load(current)
    }

    /// Every episode that has aired, in every regular season, is ticked off.
    suspend fun allSeasonsFinished(): Boolean {
        for (s in detail.regularSeasons) {
            val eps = episodes[s.number] ?: runCatching { Catalog.season(show.id, s.number) }.getOrNull() ?: return false
            if (eps.any { it.aired && !Library.isSeen(show.id, it) }) return false
        }
        return true
    }

    // When the season you're on is finished, check whether that was the whole show.
    val seenNow = Library.seenCount(show.id, current)
    var lastSeen by remember(current) { mutableStateOf(seenNow) }
    LaunchedEffect(seenNow) {
        val old = lastSeen
        lastSeen = seenNow
        val eps = episodes[current] ?: return@LaunchedEffect
        if (current <= 0 || seenNow <= old) return@LaunchedEffect
        val aired = eps.filter { it.aired }
        if (aired.isEmpty() || old >= aired.size || !aired.all { Library.isSeen(show.id, it) }) return@LaunchedEffect
        if (!allSeasonsFinished()) return@LaunchedEffect
        // Comfort shows don't get asked for a rating; a finished one still joins your watched shows.
        if (Library.isComfort(show.id)) { if (detail.hasEnded) Library.finishShow(show); return@LaunchedEffect }
        pendingWrap = true
    }
    /// Waits for any open sheet (say, the episode you just ticked off) to close first.
    LaunchedEffect(pendingWrap, Router.sheet == null) {
        if (!pendingWrap || Router.sheet != null) return@LaunchedEffect
        delay(500)
        if (Router.sheet != null) return@LaunchedEffect
        pendingWrap = false
        Haptics.success()
        Router.sheet = SheetRoute.Wrap(show)
    }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionHeader("Episodes", if (totalSeen == 0) "$totalEpisodes episodes · tick them off as you go" else "You've seen $totalSeen of $totalEpisodes")
        if (totalSeen > 0) {
            LinearProgressIndicator(progress = { totalSeen.toFloat() / maxOf(1, totalEpisodes) }, color = Theme.watch, trackColor = Color.White.copy(alpha = 0.15f),
                drawStopIndicator = {}, gapSize = 0.dp,
                modifier = Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(4.dp).clip(CircleShape))
        }
        // Season picker
        val listState = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(0, seasons.indexOfFirst { it.number == current } - 1))
        LazyRow(state = listState, contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(seasons, key = { it.number }) { s ->
                val seen = Library.seenCount(show.id, s.number)
                val on = s.number == current
                Row(
                    Modifier.clip(CircleShape).background(if (on) accent.copy(alpha = 0.28f) else surface)
                        .border(1.2.dp, if (on) accent else Color.Transparent, CircleShape)
                        .clickable { selected = s.number; Haptics.selection() }
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ProgressRing(if (s.episodeCount > 0) seen.toDouble() / s.episodeCount else 0.0, Theme.watch, Modifier.size(16.dp))
                    Text(if (s.number == 0) "Specials" else "Season ${s.number}", style = Type.subheadline.semibold(), color = Color.White)
                }
            }
        }
        seasons.firstOrNull { it.number == current }?.let { SeasonCard(show, it, episodes[it.number], surface) }
        val eps = episodes[current]
        when {
            eps != null -> {
                val next = eps.firstOrNull { it.aired && !Library.isSeen(show.id, it) }
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (ep in eps) EpisodeRow(show, ep, ep.id == next?.id, surface, accent, detail.runtimeMinutes)
                }
            }
            failed[current] == true -> Text("Couldn't load episodes — try again", style = Type.subheadline.semibold(), color = Theme.accent, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clickable { failed.remove(current); scope.launch { load(current) } }.padding(vertical = 20.dp))
            else -> Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
            }
        }
    }
}

/// A season's progress, and Mark all.
@Composable
private fun SeasonCard(show: FilmRef, info: SeasonInfo, eps: List<Episode>?, surface: Color) {
    val seen = Library.seenCount(show.id, info.number)
    val aired = eps?.filter { it.aired } ?: emptyList()
    val allSeen = aired.isNotEmpty() && aired.all { Library.isSeen(show.id, it) }
    Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(surface, RoundedCornerShape(20.dp)).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(info.name, style = Type.headline, color = Color.White)
            Text(listOfNotNull("$seen of ${info.episodeCount} watched", info.year?.toString()).joinToString(" · "), style = Type.caption, color = Color.White.copy(alpha = 0.65f))
        }
        if (aired.isNotEmpty()) {
            PillButton(if (allSeen) "Unmark all" else "Mark all watched", if (allSeen) Icons.AutoMirrored.Filled.Undo else Icons.Outlined.CheckCircleOutline, size = ControlSize.SMALL) {
                Library.setSeen(show, aired, !allSeen); Haptics.medium()
            }
        }
    }
}

@Composable
fun ProgressRing(progress: Double, tint: Color = Theme.watch, modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = 2.5.dp.toPx()
            val r = (size.minDimension - w) / 2
            val tl = Offset(size.width / 2 - r, size.height / 2 - r)
            drawCircle(Color.White.copy(alpha = 0.18f), r, style = Stroke(w))
            drawArc(tint, -90f, (360 * minOf(1.0, progress)).toFloat(), false, tl, Size(r * 2, r * 2), style = Stroke(w, cap = StrokeCap.Round))
        }
        if (progress >= 1) Icon(Icons.Filled.Check, null, tint = tint, modifier = Modifier.size(8.dp))
    }
}

@Composable
fun EpisodeRow(show: FilmRef, episode: Episode, upNext: Boolean = false, surface: Color = Theme.card, accent: Color = Theme.accent, fallbackRuntime: Int? = null) {
    val seen = Library.isSeen(show.id, episode)
    val bounce = remember { Animatable(1f) }
    LaunchedEffect(seen) { if (seen) { bounce.animateTo(1.25f, tween(110)); bounce.animateTo(1f, tween(160)) } }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(if (upNext) surface else Color.Transparent)
            .border(1.dp, if (upNext) accent.copy(alpha = 0.6f) else Color.Transparent, RoundedCornerShape(18.dp))
            .padding(vertical = if (upNext) 14.dp else 6.dp, horizontal = if (upNext) 12.dp else 4.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (upNext) Text("UP NEXT", style = Type.caption2.heavy().tracking(1.2f), color = accent)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.width(34.dp).height(44.dp).clickable(enabled = episode.aired || seen, interactionSource = remember { MutableInteractionSource() }, indication = null) {
                Library.toggleSeen(show, episode); if (seen) Haptics.light() else Haptics.medium()
            }, contentAlignment = Alignment.Center) {
                Icon(if (seen) Icons.Filled.CheckCircle else Icons.Outlined.Circle, if (seen) "Watched ${episode.code}" else "Mark ${episode.code} watched",
                    tint = if (seen) Theme.watch else Color.White.copy(alpha = if (episode.aired) 0.45f else 0.15f),
                    modifier = Modifier.size(28.dp).graphicsLayer { scaleX = bounce.value; scaleY = bounce.value })
            }
            Row(Modifier.weight(1f).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { Router.sheet = SheetRoute.EpisodeOf(show, episode) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(96.dp).height(54.dp).clip(RoundedCornerShape(8.dp)).background(Color.White.copy(alpha = 0.06f)).alpha(if (seen) 0.6f else 1f), contentAlignment = Alignment.Center) {
                    if (episode.still != null) RemoteImage(episode.still, Modifier.fillMaxSize())
                    else Icon(Icons.Filled.LiveTv, null, tint = Color.White.copy(alpha = 0.3f))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${episode.number}. ${episode.name}", style = Type.subheadline.semibold(), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val sub = if (!episode.aired) episode.airDate?.let { "Airs ${Dates.dayMonth(it)}" } ?: "Not aired yet"
                    else (episode.runtime ?: fallbackRuntime)?.takeIf { it > 0 }?.let { filmClock(it * 60.0) }
                    if (sub != null) Text(sub, style = Type.caption, color = if (!episode.aired) accent else Color.White.copy(alpha = 0.6f))
                }
            }
        }
        if (upNext) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip(prominent = true, onClick = { Watching.start(show, episode, fallbackRuntime); Haptics.medium() }) { Label("Start watching", Icons.Filled.PlayArrow) }
                Chip(onClick = { Library.setSeen(show, listOf(episode), true) }) { Label("Watched", Icons.Filled.Check) }
            }
        }
    }
}

// MARK: - One episode

@Composable
fun EpisodeSheet(show: FilmRef, episode: Episode) {
    val dismiss = LocalDismiss.current
    var palette by remember { mutableStateOf(Palette.cached(show.poster)) }
    LaunchedEffect(show.poster) { if (palette == null) palette = Palette.of(show.poster) }
    val bg by animateColorAsState(palette?.background ?: Color.Black, tween(500), label = "bg")
    val highlight = palette?.highlight ?: Theme.accent
    val seen = Library.isSeen(show.id, episode)
    Column(Modifier.fillMaxSize().background(bg)) {
        SheetBar(episode.code, leading = { CloseButton() })
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(20.dp))) {
                RemoteImage(episode.still ?: show.backdrop, Modifier.fillMaxSize())
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to bg)))
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("${show.title.uppercase()} · ${episode.code}", style = Type.caption.heavy().tracking(1.2f), color = highlight)
                Text(episode.name, style = Type.title2, color = Color.White)
                val parts = listOfNotNull(
                    episode.airDate?.let { Dates.long(it) },
                    episode.runtime?.takeIf { it > 0 }?.let { filmClock(it * 60.0) },
                    episode.communityRating?.takeIf { it > 0 }?.let { "★ " + String.format(Locale.US, "%.1f", it / 2) },
                )
                if (parts.isNotEmpty()) Text(parts.joinToString(" · "), style = Type.subheadline.semibold(), color = Color.White.copy(alpha = 0.7f))
            }
            episode.overview?.let { Text(it, style = Type.body, color = Color.White.copy(alpha = 0.85f)) }
            if (episode.aired) {
                Row(Modifier.fillMaxWidth().panel(RoundedCornerShape(26.dp)).padding(18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    PillButton(if (seen) "Watched" else "Mark as watched", if (seen) Icons.Filled.CheckCircle else Icons.Outlined.Circle, Modifier.weight(1f),
                        size = ControlSize.LARGE, fill = true, color = if (seen) Theme.watch else Color.White) {
                        Library.toggleSeen(show, episode); Haptics.medium()
                    }
                    Box(Modifier.size(50.dp).clip(CircleShape).background(Theme.accent).clickable {
                        Watching.start(show, episode, Catalog.cached(show.id)?.runtimeMinutes); dismiss()
                    }, contentAlignment = Alignment.Center) { Icon(Icons.Filled.PlayArrow, "Start watching", tint = Color.White) }
                }
            } else {
                Label(episode.airDate?.let { "Airs ${Dates.long(it)}" } ?: "Hasn't aired yet", Icons.Filled.CalendarMonth, color = highlight)
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

// MARK: - Series wrap-up

/// At the end of the whole show: give it your rating.
@Composable
fun SeriesWrapSheet(show: FilmRef) {
    val dismiss = LocalDismiss.current
    var detail by remember { mutableStateOf<FilmDetail?>(null) }
    var palette by remember { mutableStateOf<PosterPalette?>(Palette.cached(show.poster)) }
    LaunchedEffect(Unit) { if (palette == null) palette = Palette.of(show.poster) }
    LaunchedEffect(Unit) {
        detail = runCatching { Catalog.detail(show.id) }.getOrNull()
        // A finished show that has ended joins your watched shows; one still running stays in progress.
        if (detail?.hasEnded == true) Library.finishShow(show)
    }
    val bg by animateColorAsState(palette?.background ?: Color.Black, tween(500), label = "bg")
    val surface = palette?.surface ?: Theme.card
    val glow = palette?.glow
    Box(Modifier.fillMaxSize().background(bg)) {
        if (glow != null) Canvas(Modifier.fillMaxWidth().height(420.dp)) {
            drawCircle(Brush.radialGradient(listOf(glow.copy(alpha = 0.5f), Color.Transparent), center = Offset(size.width / 2, 0f), radius = size.width * 0.9f),
                size.width * 0.9f, Offset(size.width / 2, 0f))
        }
        Column(Modifier.fillMaxSize()) {
            SheetBar("", leading = { CloseButton() })
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(22.dp)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PosterView(show, width = 130.dp, corner = 12.dp)
                    Text("🎉", style = Type.largeTitle)
                    Text(if (detail?.hasEnded == false) "All caught up" else "Series complete", style = Type.largeTitle.heavy(), color = Color.White, textAlign = TextAlign.Center)
                    Text(show.title, style = Type.headline, color = Color.White.copy(alpha = 0.7f), textAlign = TextAlign.Center)
                }
                Column(Modifier.fillMaxWidth().background(surface, RoundedCornerShape(24.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("THE WHOLE SHOW", style = Type.caption.heavy().tracking(1.4f), color = Color.White.copy(alpha = 0.6f))
                    Text("Your rating for ${show.title}", style = Type.subheadline.semibold(), color = Color.White)
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        FilmRatingInput(Library.rating(show.id), dialSize = 190.dp) { Library.rate(show, it) }
                    }
                }
                PillButton("Done", prominent = true, size = ControlSize.LARGE, fill = true) { dismiss() }
                Spacer(Modifier.height(20.dp))
            }
        }
    }
}

// MARK: - Shows in progress

/// Posters of shows you're partway through, each with how far you've got.
@Composable
fun ShowProgressRow(shows: List<FilmRef>) {
    LazyRow(contentPadding = PaddingValues(horizontal = 20.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items(shows, key = { it.id }) { s ->
            FilmMenuBox(s) {
                Column(Modifier.width(112.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    PosterView(s, width = 112.dp)
                    Library.progress(s.id)?.lastSeen?.let { (se, e) ->
                        Text("Last: ${EpisodeKey.code(se, e)}", style = Type.caption.semibold(), color = Color.White.copy(alpha = 0.75f))
                    }
                }
            }
        }
    }
}

// MARK: - Currently watching

/// An episode's still, 16:9. Until it loads (or when TMDB has none) the show's backdrop, then its poster.
@Composable
fun EpisodeStill(still: String?, show: FilmRef, width: Dp = 112.dp, corner: Dp = 8.dp) {
    val shape = RoundedCornerShape(corner)
    Box(Modifier.width(width).height(width * 9f / 16f).clip(shape).background(Theme.card).border(0.5.dp, Color.White.copy(alpha = 0.1f), shape), contentAlignment = Alignment.Center) {
        val url = still ?: show.backdrop
        if (url != null) RemoteImage(url, Modifier.fillMaxSize())
        else PosterView(show, width = width * 9f / 16f * 2f / 3f, corner = corner, glows = false)
    }
}

/// Shows you've pinned, at the top of Home: the next episode to tick off or start.
@Composable
fun CurrentlyWatchingSection(shows: List<FilmRef>) {
    val screen = LocalConfiguration.current.screenWidthDp.dp
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionHeader("Currently watching", "Tick off the next episode")
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
            flingBehavior = androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior(rememberLazyListState())) {
            items(shows, key = { it.id }) { s ->
                CurrentlyWatchingCard(s, Modifier.width(if (shows.size == 1) screen - 32.dp else minOf(340.dp, screen - 64.dp)))
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CurrentlyWatchingCard(show: FilmRef, modifier: Modifier = Modifier) {
    var detail by remember(show.id) { mutableStateOf<FilmDetail?>(null) }
    var next by remember(show.id) { mutableStateOf<Episode?>(null) }
    var caughtUp by remember(show.id) { mutableStateOf(false) }
    var loaded by remember(show.id) { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val seenCount = Library.progress(show.id)?.seen?.size ?: 0

    /// The first aired episode you haven't ticked off, season by season. When you're caught up,
    /// the next one to air (if TMDB knows it).
    LaunchedEffect(show.id, seenCount) {
        val d = runCatching { Catalog.detail(show.id) }.getOrNull() ?: run { loaded = true; return@LaunchedEffect }
        detail = d
        for (s in d.regularSeasons) {
            if (Library.seenCount(show.id, s.number) >= s.episodeCount) continue
            val eps = runCatching { Catalog.season(show.id, s.number) }.getOrNull() ?: break
            eps.firstOrNull { it.aired && !Library.isSeen(show.id, it) }?.let { next = it; caughtUp = false; loaded = true; return@LaunchedEffect }
            // The rest of this season hasn't aired, so neither has anything after it.
            if (eps.any { !it.aired }) break
        }
        next = d.nextEpisode; caughtUp = true; loaded = true
    }

    Box(modifier) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(Theme.card)
                .combinedClickable(onClick = { next?.let { Router.sheet = SheetRoute.EpisodeOf(show, it) } ?: Router.open(show) },
                    onLongClick = { Haptics.heavy(); menu = true })
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.clickable { Router.open(show) }) { EpisodeStill(next?.still, show, 112.dp) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(show.title, style = Type.headline, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val n = next
                    when {
                        n != null -> {
                            Text("${if (caughtUp) "NEXT TO AIR" else "UP NEXT"} · ${n.code}", style = Type.caption2.heavy().tracking(1f), color = Theme.accent)
                            Text(n.name, style = Type.subheadline.semibold(), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            if (caughtUp) n.airDate?.let { Text("Airs ${Dates.weekdayDayMonth(it)}", style = Type.caption, color = Theme.dim) }
                            else (n.runtime ?: detail?.runtimeMinutes)?.takeIf { it > 0 }?.let { Text(filmClock(it * 60.0), style = Type.caption, color = Theme.dim) }
                        }
                        loaded -> Text(if (detail?.hasEnded == true) "You've seen every episode" else "All caught up", style = Type.subheadline, color = Theme.dim)
                        else -> CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.padding(top = 6.dp).size(18.dp))
                    }
                }
            }
            val n = next
            if (n != null && !caughtUp) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip(prominent = true, onClick = { Library.setSeen(show, listOf(n), true); Haptics.medium() }) { Label("Watched", Icons.Filled.Check) }
                    Chip(onClick = { Watching.start(show, n, detail?.runtimeMinutes); Haptics.medium() }) { Label("Start", Icons.Filled.PlayArrow) }
                }
            }
        }
        DropdownMenu(menu, { menu = false }, containerColor = androidx.compose.ui.graphics.Color(0xFF1C1C1E)) {
            MenuItem("Open show", Icons.Filled.LiveTv) { menu = false; Router.open(show) }
            MenuItem("Remove from Currently watching", Icons.Outlined.PushPin, destructive = true) { menu = false; Library.toggleCurrentlyWatching(show) }
        }
    }
}
