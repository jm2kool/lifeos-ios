package com.jm2kool.matinee.ui

import android.content.Intent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Weekend
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.FilmArt
import com.jm2kool.matinee.data.Palette
import com.jm2kool.matinee.data.PosterPalette
import com.jm2kool.matinee.data.WatchProvider
import com.jm2kool.matinee.data.WatchProviders
import com.jm2kool.matinee.data.largePoster
import com.jm2kool.matinee.model.Dates
import com.jm2kool.matinee.model.FilmDetail
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Watching
import com.jm2kool.matinee.model.filmClock
import com.jm2kool.matinee.ui.Type.bold
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

@Composable
fun ShowView(film: FilmRef) {
    var detail by remember(film.id) { mutableStateOf(Catalog.cached(film.id)) }
    var failed by remember(film.id) { mutableStateOf(false) }
    var art by remember(film.id) { mutableStateOf<FilmArt?>(null) }
    var artLoaded by remember(film.id) { mutableStateOf(false) }
    var palette by remember(film.id) { mutableStateOf<PosterPalette?>(null) }
    var trailerKey by remember(film.id) { mutableStateOf<String?>(null) }
    val ctx = LocalContext.current

    val ref = (detail?.ref ?: film).let { r -> r.copy(title = r.title.ifEmpty { film.title }, poster = r.poster ?: film.poster) }
    /// A textless poster when TMDB has one (the title is drawn separately as the logo).
    val heroURL = art?.poster ?: if (artLoaded || failed) (ref.largePoster ?: ref.poster) else null

    LaunchedEffect(film.id) { trailerKey = Catalog.trailer(film.id) }
    LaunchedEffect(film.id) {
        try {
            val d = Catalog.detail(film.id)
            detail = d
            Library.hydrate(film, d)
            art = Catalog.art(d.ref.id)
            artLoaded = true
        } catch (e: Exception) { failed = true; artLoaded = true }
    }
    LaunchedEffect(heroURL) {
        if (heroURL == null) return@LaunchedEffect
        palette = Palette.cached(heroURL) ?: Palette.of(heroURL)
    }

    /// The page takes its colour from the poster: deep enough for white text, never washed out.
    val bg by animateColorAsState(palette?.background ?: Color.Black, tween(700), label = "bg")
    val surface by animateColorAsState(palette?.surface ?: Theme.card, tween(700), label = "surface")
    val highlight = palette?.highlight ?: Theme.accent

    fun playTrailer() {
        val k = trailerKey
        if (k != null) { Haptics.light(); Router.trailer = k to ref.title }
        else Library.toast = com.jm2kool.matinee.model.Toast("No trailer for this one yet", Icons.Filled.PlayArrow)
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(bg)) {
        val pageHeight = maxHeight
        val scroll = rememberScrollState()
        LaunchedEffect(Unit) {
            com.jm2kool.matinee.data.Demo.scrollTo?.let { kotlinx.coroutines.delay(5000); scroll.animateScrollTo(it) }
        }
        Column(Modifier.fillMaxSize().verticalScroll(scroll)) {
            Header(ref, detail, art, artLoaded || failed, heroURL, bg, highlight, trailerKey != null, pageHeight, ::playTrailer, scroll)
            Column(
                Modifier.fillMaxWidth().background(bg).padding(top = 6.dp, bottom = 60.dp),
                verticalArrangement = Arrangement.spacedBy(26.dp),
            ) {
                ActionPanel(ref, detail, Modifier.padding(horizontal = 16.dp))
                detail?.let { SeasonsSection(ref, it, surface, highlight) }
                val d = detail
                when {
                    d != null -> { Info(ref, d, surface); WatchProvidersSection(ref, surface) }
                    failed -> EmptyState(Icons.Filled.LiveTv, "Couldn't load details", "You can still log, rate and save this show.")
                    else -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(26.dp))
                    }
                }
                YourActivity(ref, surface, highlight)
            }
        }
        TopBar(overImage = true) { ShowMenu(ref, heroURL, art, palette, ctx) }
    }
}

/// Apple Music–style: a textless poster fills the screen, the show's logo is the title, and as you
/// scroll the logo shrinks into the top bar and stays there.
@Composable
private fun Header(
    ref: FilmRef, detail: FilmDetail?, art: FilmArt?, ready: Boolean, heroURL: String?, bg: Color, highlight: Color,
    hasTrailer: Boolean, height: androidx.compose.ui.unit.Dp, playTrailer: () -> Unit,
    scroll: androidx.compose.foundation.ScrollState,
) {
    val d = LocalDensity.current
    val safeTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val pinTop = with(d) { (safeTop + 8.dp).toPx() }
    var logoTop by remember { mutableFloatStateOf(Float.NaN) }        // in content coordinates
    var logoW by remember { mutableFloatStateOf(1f) }
    var logoH by remember { mutableFloatStateOf(1f) }
    var metaTop by remember { mutableFloatStateOf(Float.NaN) }
    val travel = with(d) { 220.dp.toPx() }
    val fitH = with(d) { 30.dp.toPx() }
    val fitW = with(d) { 180.dp.toPx() }

    Box(Modifier.fillMaxWidth().height(height).zIndex(1f)) {       // keeps the pinned logo above the page as it scrolls
        // Tap the poster for the trailer, full screen.
        RemoteImage(heroURL, Modifier.fillMaxSize().clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { playTrailer() })
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
            0f to Color.Black.copy(alpha = 0.45f), 0.16f to Color.Transparent, 0.5f to Color.Transparent,
            0.78f to bg.copy(alpha = 0.8f), 1f to bg,
        )))
        Column(Modifier.align(Alignment.BottomCenter).padding(bottom = 18.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.widthIn(max = 300.dp).onGloballyPositioned {
                logoTop = it.positionInRoot().y + scroll.value
                logoW = it.size.width.toFloat(); logoH = it.size.height.toFloat()
            }) {
                TitleArt(ref.title, art?.logo, aspect = art?.logoAspect ?: 3.0, maxWidth = 280.dp, maxHeight = 110.dp, fontSize = 40f, ready = ready,
                    modifier = Modifier.graphicsLayer {
                        if (logoTop.isNaN()) return@graphicsLayer
                        // Shrink toward the top bar as you scroll, then stay pinned there.
                        // Fit between the back button and the ••• menu: at most 30dp tall and 180dp wide.
                        val fit = min(1f, min(fitH / max(logoH, 1f), fitW / max(logoW, 1f)))
                        val distance = logoTop - scroll.value - pinTop
                        val p = min(1f, max(0f, 1 - distance / travel))
                        val s = 1 - p * (1 - fit)
                        transformOrigin = TransformOrigin(0.5f, 0f)
                        scaleX = s; scaleY = s
                        translationY = max(0f, -distance)
                    })
            }
            Column(
                Modifier.padding(horizontal = 22.dp)
                    .onGloballyPositioned { metaTop = it.positionInRoot().y + scroll.value }
                    .graphicsLayer {
                        if (metaTop.isNaN()) return@graphicsLayer
                        val y = (metaTop - scroll.value) / density
                        alpha = min(1f, max(0f, (y - 90) / 160))
                    },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val meta = buildAnnotatedString {
                    detail?.genres?.firstOrNull()?.let { g ->
                        withStyle(SpanStyle(color = highlight)) { append(g.uppercase()) }
                        append("  ·  ")
                    }
                    ref.year?.let { append(yearSpan(it, detail)) }
                    val n = detail?.regularSeasons?.size ?: 0
                    if (n > 0) append("  ·  ${if (n == 1) "1 season" else "$n seasons"}")
                    else detail?.runtimeMinutes?.takeIf { it > 0 }?.let { append("  ·  ${it / 60}h ${it % 60}m") }
                    detail?.communityRating?.takeIf { it > 0 }?.let {
                        append("  ·  ")
                        withStyle(SpanStyle(color = Theme.star)) { append("★ ") }
                        append(String.format(Locale.US, "%.1f", it / 2))
                    }
                }
                Text(meta, style = Type.subheadline.semibold(), color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center)
                ref.category?.let { c ->
                    Text("${c.flag}  ${c.label}", style = Type.footnote.semibold(), color = Color.White.copy(alpha = 0.75f))
                }
                detail?.creators?.takeIf { it.isNotEmpty() }?.let { c ->
                    Text(buildAnnotatedString {
                        append("Created by ")
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(c.take(2).joinToString(", ")) }
                    }, style = Type.subheadline, color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center)
                }
                if (hasTrailer) {
                    Row(Modifier.padding(top = 2.dp).clip(CircleShape).background(Theme.chip).clickable(onClick = playTrailer).padding(horizontal = 14.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(15.dp))
                        Text("Trailer", style = Type.footnote.bold(), color = Color.White)
                    }
                }
                val pulse = rememberInfiniteTransition(label = "pulse")
                val a by pulse.animateFloat(0.25f, 0.6f, infiniteRepeatable(tween(1000), RepeatMode.Reverse), label = "a")
                Icon(Icons.Filled.KeyboardArrowUp, null, tint = Color.White.copy(alpha = a), modifier = Modifier.padding(top = 4.dp).size(30.dp))
            }
        }
    }
}

/// "2019–2020" for an ended show, "2023–" while it's still running.
private fun yearSpan(y: Int, d: FilmDetail?): String {
    if (d == null) return y.toString()
    if (d.hasEnded) return d.lastYear?.takeIf { it != y }?.let { "$y–$it" } ?: y.toString()
    return "$y–"
}

@Composable
private fun ShowMenu(ref: FilmRef, heroURL: String?, art: FilmArt?, palette: PosterPalette?, ctx: android.content.Context) {
    var open by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Box {
        IconCircle(Icons.Filled.MoreHoriz, "More", size = 38.dp) { open = true }
        DropdownMenu(open, { open = false }, containerColor = Color(0xFF1C1C1E)) {
            MenuItem("Share", Icons.Filled.Share) {
                open = false
                val text = "${ref.title}${ref.year?.let { " ($it)" } ?: ""} — on my watch list in Matinee"
                ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null))
            }
            MenuItem("Share as a story card", Icons.Outlined.Image, enabled = heroURL != null) {
                open = false
                scope.launch {
                    ShareCard.share(ctx, ref, heroURL, art?.logo, Library.rating(ref.id), Library.isLiked(ref.id), palette?.accent ?: Theme.accent)
                }
            }
            MenuItem("Add to list…", Icons.AutoMirrored.Filled.PlaylistAdd) { open = false; Router.sheet = SheetRoute.AddToList(ref) }
            if (Library.isFavorite(ref.id)) MenuItem("Remove from favourites", Icons.Outlined.StarOutline) { open = false; Library.removeFavorite(ref) }
            else MenuItem(if (Library.favoritesFull) "Favourites are full — edit in Settings" else "Add to favourites", Icons.Filled.Star, enabled = !Library.favoritesFull) {
                open = false; Library.addFavorite(ref)
            }
            if (Library.isWatched(ref.id)) MenuItem("Remove from watched", Icons.Outlined.VisibilityOff, destructive = true) { open = false; Library.toggleWatched(ref) }
        }
    }
}

// MARK: Actions — the one place to watch, like, save, rate and log

@Composable
private fun ActionPanel(ref: FilmRef, detail: FilmDetail?, modifier: Modifier) {
    val watched = Library.isWatched(ref.id)
    val liked = Library.isLiked(ref.id)
    val saved = Library.inWatchlist(ref.id)
    Column(modifier.fillMaxWidth().panel(RoundedCornerShape(28.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth()) {
            ToggleAction(if (watched) "Watched" else "Watch", if (watched) Icons.Filled.Visibility else Icons.Outlined.Visibility, watched, Theme.watch) { Library.toggleWatched(ref) }
            ToggleAction(if (liked) "Liked" else "Like", if (liked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, liked, Theme.heart) { Library.toggleLike(ref) }
            ToggleAction(if (saved) "In watchlist" else "Watchlist", if (saved) Icons.Filled.Schedule else Icons.Outlined.Schedule, saved, Theme.list) { Library.toggleWatchlist(ref) }
        }
        WatchControl(ref)
        WatchExtras(ref)
        Hairline()
        if (Library.isComfort(ref.id)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(vertical = 6.dp)) {
                Icon(Icons.Filled.Weekend, null, tint = Theme.star, modifier = Modifier.size(32.dp))
                Text("A comfort show", style = Type.headline, color = Color.White)
                Text("Watch it as often as you like — Matinee won't ask you to rate it.", style = Type.caption, color = Color.White.copy(alpha = 0.65f), textAlign = TextAlign.Center)
            }
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (Library.rating(ref.id) == null) "Rate the show" else "Your rating for the show", style = Type.caption.semibold(), color = Color.White.copy(alpha = 0.65f))
                FilmRatingInput(Library.rating(ref.id)) { Library.rate(ref, it) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            PillButton(if (watched) "Log again or review" else "Review or log", Icons.Filled.Edit, Modifier.weight(1f), prominent = true, size = ControlSize.LARGE, fill = true) {
                Router.sheet = SheetRoute.Log(ref, null)
            }
            Box(Modifier.size(50.dp).clip(CircleShape).background(Theme.chip).clickable { Router.sheet = SheetRoute.AddToList(ref) }, contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.PlaylistAdd, "Add to list", tint = Color.White)
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.ToggleAction(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, on: Boolean, color: Color, action: () -> Unit) {
    val scale = remember { androidx.compose.animation.core.Animatable(1f) }
    LaunchedEffect(on) { if (on) { scale.animateTo(1.25f, tween(110)); scale.animateTo(1f, tween(160)) } }
    Column(
        Modifier.weight(1f).clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) {
            action(); if (on) Haptics.light() else Haptics.medium()
        },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, title, tint = if (on) color else Color.White.copy(alpha = 0.8f), modifier = Modifier.height(30.dp).size(28.dp).graphicsLayer { scaleX = scale.value; scaleY = scale.value })
        Text(title, style = Type.caption.semibold(), color = if (on) color else Color.White.copy(alpha = 0.65f))
    }
}

/// Intermission mode: the episode you're on, paused or playing.
@Composable
private fun WatchControl(ref: FilmRef) {
    val s = Watching.session(ref.id) ?: return       // shows start from an episode, in the list below
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (s.running) {
                val now by tickingNow(30_000)
                Label("${s.episodeCode ?: "Watching"} · ${filmClock(s.elapsed(now))}${s.runtime?.let { " of ${filmClock(it)}" } ?: ""}",
                    Icons.Filled.PlayCircle, modifier = Modifier.weight(1f))
                Chip(prominent = true, onClick = { Router.sheet = SheetRoute.IntermissionOf(s.id) }) { Label("Intermission", Icons.Filled.Pause) }
            } else {
                Label("Paused at ${filmClock(s.banked)}", Icons.Filled.PauseCircle, modifier = Modifier.weight(1f))
                Chip(prominent = true, onClick = { Watching.resume(s.id) }) { Label("Resume", Icons.Filled.PlayArrow) }
            }
        }
        s.lastStop?.takeIf { !s.running }?.let { IntermissionRow(it) }
    }
}

/// Pin a show to Currently watching on Home, and mark a comfort show so it's never asked for a rating.
@Composable
private fun WatchExtras(ref: FilmRef) {
    val comfort = Library.isComfort(ref.id)
    val pinned = Library.isCurrentlyWatching(ref.id)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip(Modifier.weight(1f), prominent = pinned, onClick = { Library.toggleCurrentlyWatching(ref); Haptics.medium() }) {
            Label("Currently watching", if (pinned) Icons.Filled.Check else Icons.Outlined.PushPin)
        }
        Chip(Modifier.weight(1f), prominent = comfort, onClick = { Library.toggleComfort(ref); Haptics.medium() }) {
            Label("Comfort show", if (comfort) Icons.Filled.Weekend else Icons.Outlined.Weekend)
        }
    }
}

// MARK: Info

@Composable
private fun Info(ref: FilmRef, d: FilmDetail, surface: Color) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        d.tagline?.let { Text(it.uppercase(), style = Type.caption.semibold().tracking(1f), color = Color.White.copy(alpha = 0.65f)) }
        d.overview?.let {
            Text(it, style = Type.body, color = Color.White.copy(alpha = 0.85f), maxLines = if (expanded) Int.MAX_VALUE else 4, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.animateContentSize().clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { expanded = !expanded })
        }
    }
    if (d.genres.isNotEmpty()) {
        ChipRow(Modifier.padding(top = 0.dp)) {
            for (g in d.genres) {
                // Genres Matinee can browse open their page; the rest are just labels.
                if (Catalog.genreNamed(g) != null) PillButton(g, size = ControlSize.SMALL) { Router.push(GenreRoute(g)) }
                else Text(g, style = Type.footnote.semibold(), color = Color.White, modifier = Modifier.clip(CircleShape).background(Theme.chip).padding(horizontal = 12.dp, vertical = 6.dp))
            }
        }
    }

    d.communityRating?.takeIf { it > 0 }?.let { r ->
        Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(surface, RoundedCornerShape(22.dp)).padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("COMMUNITY", style = Type.caption2.heavy().tracking(1.2f), color = Color.White.copy(alpha = 0.65f))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(String.format(Locale.US, "%.1f", r / 2), style = Type.largeTitle.copy(fontSize = 40.sp, lineHeight = 44.sp), color = Color.White)
                    Icon(Icons.Filled.Star, null, tint = Theme.star, modifier = Modifier.size(20.dp))
                }
                d.voteCount?.let { Text("${compact(it)} ratings on TMDB", style = Type.caption, color = Color.White.copy(alpha = 0.65f)) }
            }
            StarRating(Math.round(r) / 2.0, 18.dp, 3.dp)
        }
    }

    if (d.cast.isNotEmpty()) {
        Column {
            SectionHeader("Cast")
            LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                items(d.cast, key = { it.id }) { p ->
                    Column(Modifier.width(84.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.size(72.dp).clip(CircleShape).background(surface), contentAlignment = Alignment.Center) {
                            Text(p.name.take(1), style = Type.title2, color = Color.White.copy(alpha = 0.65f))
                            if (p.photo != null) RemoteImage(p.photo, Modifier.fillMaxSize())
                        }
                        Text(p.name, style = Type.caption.semibold(), color = Color.White, maxLines = 2, textAlign = TextAlign.Center)
                        if (p.role.isNotEmpty()) Text(p.role, style = Type.caption2, color = Color.White.copy(alpha = 0.65f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader("Details")
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(surface, RoundedCornerShape(18.dp))) {
            ref.category?.let { DetailRow("Category", "${it.flag}  ${it.label}") }
            d.status?.let { DetailRow("Status", if (it == "Returning Series") "Still running" else it) }
            if (d.networks.isNotEmpty()) DetailRow(if (d.networks.size > 1) "Networks" else "Network", d.networks.take(3).joinToString(", "))
            d.nextEpisode?.let { n -> n.airDate?.let { DetailRow("Next episode", "${n.code} · ${Dates.dayMonth(it)}") } }
            if (d.creators.isNotEmpty()) DetailRow("Created by", d.creators.joinToString(", "))
            d.runtimeMinutes?.takeIf { it > 0 }?.let { DetailRow("Episode length", "$it minutes") }
            if (d.countries.isNotEmpty()) DetailRow("Country", d.countries.take(3).joinToString(", "))
        }
    }

    if (d.similar.isNotEmpty()) {
        Column {
            SectionHeader("More like this")
            PosterRow(d.similar, width = 104.dp)
        }
    }
}

private fun compact(n: Int): String = when {
    n >= 1_000_000 -> String.format(Locale.US, "%.1fM", n / 1_000_000.0)
    n >= 1_000 -> String.format(Locale.US, "%.1fK", n / 1_000.0).replace(".0K", "K")
    else -> n.toString()
}

@Composable
private fun DetailRow(k: String, v: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Text(k, style = Type.subheadline, color = Color.White.copy(alpha = 0.65f))
        Spacer(Modifier.weight(1f).widthIn(min = 12.dp))
        Text(v, style = Type.subheadline, color = Color.White, textAlign = TextAlign.End, modifier = Modifier.widthIn(max = 230.dp))
    }
}

@Composable
private fun YourActivity(ref: FilmRef, surface: Color, highlight: Color) {
    val mine = Library.entries(ref.id)
    if (mine.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader("Your diary", if (mine.size == 1) "Watched once" else "Watched ${mine.size} times")
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (e in mine) {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(surface).clickable { Router.sheet = SheetRoute.Log(e.film, e) }.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(Dates.abbreviated(e.watchedOn), style = Type.subheadline.semibold(), color = Color.White)
                        if (e.rewatch) Icon(Icons.Filled.Repeat, null, tint = Theme.watch, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.weight(1f))
                        SmallRating(e.rating)
                        Liked(e.liked)
                    }
                    if (e.review.isNotEmpty()) Text(e.review, style = Type.subheadline, color = Color.White.copy(alpha = 0.8f), maxLines = 4, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

// MARK: Where to watch

/// Where to watch in India: streaming, free, rent and buy, each opening the service.
@Composable
fun WatchProvidersSection(film: FilmRef, surface: Color = Theme.card) {
    var providers by remember(film.id) { mutableStateOf<WatchProviders?>(null) }
    var loaded by remember(film.id) { mutableStateOf(false) }
    val ctx = LocalContext.current
    LaunchedEffect(film.id) { providers = Catalog.providers(film.id); loaded = true }
    val justWatch = "https://www.justwatch.com/in/search?q=${java.net.URLEncoder.encode(film.title, "UTF-8")}"
    fun openURL(u: String) = runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(u))) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader("Where to watch", "In India")
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(surface, RoundedCornerShape(22.dp)).padding(16.dp)) {
            val p = providers
            when {
                p != null && !p.isEmpty -> Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    for ((label, list) in listOf("Stream" to p.stream, "Free" to p.free, "Rent" to p.rent, "Buy" to p.buy)) {
                        if (list.isEmpty()) continue
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(label.uppercase(), style = Type.caption2.heavy().tracking(1.2f), color = Color.White.copy(alpha = 0.6f))
                            Row(Modifier.horizontalScrollCompat(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                for (w in list) ProviderTile(w) { openURL(w.searchURL(film.title) ?: p.link ?: justWatch) }
                            }
                        }
                    }
                    Text("Availability from JustWatch", style = Type.caption2, color = Color.White.copy(alpha = 0.5f))
                }
                loaded -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Not streaming, renting or selling in India right now.", style = Type.subheadline, color = Color.White.copy(alpha = 0.8f))
                    PillButton("Check JustWatch for updates", Icons.Filled.Search, size = ControlSize.SMALL) { openURL(justWatch) }
                }
                else -> Box(Modifier.fillMaxWidth().height(60.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                }
            }
        }
    }
}

@Composable
private fun ProviderTile(p: WatchProvider, onClick: () -> Unit) {
    Column(Modifier.width(64.dp).clickable(onClick = onClick), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        RemoteImage(p.logo, Modifier.size(52.dp).clip(RoundedCornerShape(12.dp)))
        Text(p.name, style = Type.caption2.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun Modifier.horizontalScrollCompat(): Modifier = this.horizontalScroll(rememberScrollState())
