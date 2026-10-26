package com.jm2kool.matinee.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.Palette
import com.jm2kool.matinee.data.Taste
import com.jm2kool.matinee.data.adjusted
import com.jm2kool.matinee.data.largePoster
import com.jm2kool.matinee.model.EpisodeKey
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.LibraryDoc
import com.jm2kool.matinee.model.Persona
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.Profile
import com.jm2kool.matinee.model.RatingStyle
import com.jm2kool.matinee.model.Score
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Locale
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

@Composable
fun ProfileView() {
    val p = Library.doc.profile
    var meshColors by remember { mutableStateOf(FavoritesMesh.fallback) }
    var learning by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val favs = Library.favorites

    LaunchedEffect(favs.map { it.poster ?: it.id }) {
        // Up to four colours from every favourite poster (and its backdrop), so the card mixes all of them.
        val ui = ArrayList<Int>()
        for (f in favs) for (url in listOf(f.largePoster ?: f.poster, f.backdrop)) {
            val pal = Palette.of(url) ?: continue
            ui += pal.colors.take(if (url == f.backdrop) 2 else 4)
        }
        val vivid = ArrayList<Int>()
        for (c in ui) {
            val v = adjusted(c, maxBrightness = 0.95f, minSaturation = 0.5f, minBrightness = 0.55f)
            // Skip near-duplicates so the mix keeps its variety.
            if (vivid.isNotEmpty() && ui.size > 6 && vivid.any { close(it, v) }) continue
            vivid += v
        }
        meshColors = if (vivid.isEmpty()) FavoritesMesh.fallback else vivid.map { Color(it) }
    }
    // Your character keeps learning from your watchlist and ratings.
    LaunchedEffect(Taste.signature()) { kotlinx.coroutines.delay(1000); runCatching { Taste.learnFromLibrary() } }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        // Like Apple Card: a slowly shifting blend of colour — here drawn from your favourite posters.
        FavoritesMesh(meshColors, Modifier.fillMaxWidth().height(620.dp))
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            TopBar("Profile", onBack = null) { IconCircle(Icons.Filled.Settings, "Settings", 38.dp, Color.Black.copy(alpha = 0.25f)) { Router.sheet = SheetRoute.Settings } }
            // Identity
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.clip(CircleShape).clickable { Router.sheet = SheetRoute.EditProfile }) { Avatar(p, 92.dp) }
                Text(p.name.ifEmpty { "Drama fan" }, style = Type.title, color = Color.White)
                Text("On this phone", style = Type.subheadline, color = Theme.dim)
                if (p.bio.isNotEmpty()) Text(p.bio, style = Type.body, color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 30.dp))
                PillButton("Edit profile", Icons.Filled.Edit, Modifier.padding(top = 4.dp)) { Router.sheet = SheetRoute.EditProfile }
            }
            // Stats
            Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth().panel(RoundedCornerShape(24.dp)).padding(vertical = 16.dp)) {
                Stat(Library.watchedFilms.size, "Shows") { Router.push(CollectionRoute(CollectionKind.Watched)) }
                Stat(Library.thisYearCount, "This year", null)
                Stat(Library.doc.lists.size, "Lists", null)
                Stat(Library.doc.watchlist.size, "Watchlist") { Router.push(CollectionRoute(CollectionKind.Watchlist)) }
            }
            if (Library.currentlyWatching.isNotEmpty()) {
                Column {
                    SectionHeader("Currently watching")
                    WatchingNowRow(Library.currentlyWatching)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader("Favourites") { TextLink(if (favs.isEmpty()) "Add" else "Edit") { Router.sheet = SheetRoute.EditFavorites } }
                if (favs.isEmpty()) Text("Pick up to eight shows to show off on your profile.", style = Type.subheadline, color = Theme.dim, modifier = Modifier.padding(horizontal = 20.dp))
                else PosterGrid(favs, modifier = Modifier.padding(horizontal = 16.dp))
            }
            Ratings()
            val tags = Library.allTags
            if (tags.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Tags")
                    ChipRow { for (t in tags) PillButton("#$t") { Router.push(CollectionRoute(CollectionKind.Tag(t))) } }
                }
            }
            if (Library.doc.liked.isNotEmpty()) {
                Column {
                    SectionHeader("Likes") { TextLink("See all") { Router.push(CollectionRoute(CollectionKind.Liked)) } }
                    PosterRow(Library.doc.liked.asReversed().take(12), width = 92.dp)
                }
            }
            // Your drama character lives at the very bottom.
            val persona = Taste.profile.persona
            if (persona != null) {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PersonaCard(persona)
                    Text(characterSource(), style = Type.caption, color = Theme.dim, modifier = Modifier.padding(start = 6.dp))
                    Text("Retake the swipe quiz", style = Type.footnote.semibold(), color = Theme.accent, modifier = Modifier.padding(start = 6.dp).clickable { Taste.showQuiz = true })
                }
            } else {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PillButton("Find your drama character", Icons.Filled.AutoAwesome, size = ControlSize.LARGE, fill = true) { Taste.showQuiz = true }
                    if (Library.doc.watchlist.isNotEmpty() || Library.doc.ratings.isNotEmpty()) {
                        PillButton(if (learning) "Reading your shows…" else "Work it out from my watchlist", Icons.Filled.AutoFixHigh, prominent = true,
                            size = ControlSize.LARGE, fill = true, enabled = !learning) {
                            scope.launch { learning = true; runCatching { Taste.learnFromLibrary(force = true) }; learning = false }
                        }
                    }
                }
            }
            BottomSpace(20.dp)
        }
    }
}

private fun characterSource(): String {
    val n = Taste.profile.libraryFilms ?: 0
    val quiz = Taste.profile.seen > 0
    return when {
        quiz && n > 0 -> "From your swipe quiz and $n shows you've saved, rated or liked."
        !quiz && n > 0 -> "Worked out from $n shows you've saved, rated or liked."
        else -> "From your swipe quiz."
    }
}

private fun close(a: Int, b: Int): Boolean {
    val ca = Color(a); val cb = Color(b)
    return abs(ca.red - cb.red) + abs(ca.green - cb.green) + abs(ca.blue - cb.blue) < 0.18f
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Stat(n: Int, label: String, onClick: (() -> Unit)?) {
    Column(Modifier.weight(1f).then(if (onClick != null) Modifier.clickableNoRipple(onClick = onClick) else Modifier),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("$n", style = Type.title2.copy(fontSize = 24.sp), color = Color.White)
        Text(label, style = Type.caption, color = Theme.dim)
    }
}

@Composable
private fun Ratings() {
    val bins = Library.ratingHistogram
    val peak = max(1, bins.maxOrNull() ?: 1)
    val stars = Prefs.ratingStyle == RatingStyle.STARS
    val n = Library.watchedRatings.size
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader("Ratings", Library.averageRating?.let {
            if (stars) "Average ${String.format(Locale.US, "%.1f", Score.toStars(it))} ★ across $n shows" else "Average score ${it.roundToInt()} across $n shows"
        } ?: "Rate shows to see your spread")
        Row(Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(112.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (i in 0 until 10) {
                Column(Modifier.weight(1f).fillMaxHeight().clickableNoRipple(bins[i] > 0) { Router.push(CollectionRoute(CollectionKind.Rated(i))) },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.Bottom)) {
                    if (bins[i] > 0) Text("${bins[i]}", style = Type.caption2.copy(fontSize = 9.sp), color = Theme.dim)
                    Box(Modifier.fillMaxWidth().height(max(4f, 80f * bins[i] / peak).dp).clip(RoundedCornerShape(3.dp))
                        .background(ScoreColors.color(i * 10 + 5.0).copy(alpha = if (bins[i] == 0) 0.12f else if (bins[i] == peak) 1f else 0.55f)))
                    // Each band of ten points is one half star.
                    Text(if (stars) (if (i % 2 == 1) "${(i + 1) / 2}★" else " ") else "${i * 10 + 10}", style = Type.caption2.copy(fontSize = 8.sp), color = Theme.dim)
                }
            }
        }
    }
}

/// The shows you've pinned, each with a still from the furthest episode you've seen.
@Composable
fun WatchingNowRow(shows: List<FilmRef>) {
    LazyRow(contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items(shows, key = { it.id }) { s ->
            val last = Library.progress(s.id)?.lastSeen
            var still by remember(s.id, last) { mutableStateOf<String?>(null) }
            LaunchedEffect(s.id, last) {
                val (se, e) = last ?: return@LaunchedEffect
                still = runCatching { Catalog.season(s.id, se) }.getOrNull()?.firstOrNull { it.number == e }?.still
            }
            FilmMenuBox(s) {
                Column(Modifier.width(176.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    EpisodeStill(still, s, 176.dp, 10.dp)
                    Text(s.title, style = Type.caption.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    last?.let { Text("Up to ${EpisodeKey.code(it.first, it.second)}", style = Type.caption2.semibold(), color = Theme.accent) }
                }
            }
        }
    }
}

/// Genre bars, era and traits — used on the reveal and on your profile.
@Composable
fun PersonaCard(persona: Persona, compact: Boolean = true) {
    Column(Modifier.fillMaxWidth().panel(RoundedCornerShape(24.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (compact) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(persona.emoji, style = Type.largeTitle)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("YOUR DRAMA CHARACTER", style = Type.caption2.heavy().tracking(1.2f), color = Theme.dim)
                Text(persona.name, style = Type.title3, color = Color.White)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((i, g) in persona.topGenres.withIndex()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(g, style = Type.subheadline.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(110.dp))
                    Box(Modifier.weight(1f).height(10.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.08f))) {
                        Box(Modifier.fillMaxWidth(persona.genreShares.getOrElse(i) { 0.3 }.toFloat().coerceIn(0.02f, 1f)).fillMaxHeight().clip(CircleShape)
                            .background(if (i == 0) Theme.accent else Theme.accent.copy(alpha = 0.55f)))
                    }
                }
            }
        }
        ChipRow(padding = 0.dp) {
            for (t in listOf(persona.era) + persona.traits) Text(t, style = Type.caption.semibold(), color = Theme.accent,
                modifier = Modifier.clip(CircleShape).background(Theme.accent.copy(alpha = 0.16f)).padding(horizontal = 10.dp, vertical = 6.dp))
        }
    }
}

// MARK: - Editors

@Composable
fun ProfileEditor() {
    val dismiss = LocalDismiss.current
    var p by remember { mutableStateOf(Library.doc.profile) }
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch { avatarJPEG(ctx, uri)?.let { p = p.copy(avatarData = it) } }
    }
    fun pick() = picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    Column(Modifier.fillMaxSize().background(Theme.bg).imePadding()) {
        SheetBar("Edit profile", leading = { CloseButton() }, trailing = { SaveButton { Library.setProfile(p); dismiss() } })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.clickableNoRipple { pick() }) {
                    Avatar(p, 96.dp)
                    Box(Modifier.align(Alignment.BottomEnd).size(30.dp).clip(CircleShape).background(Theme.accent).border(2.dp, Color.Black, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.CameraAlt, null, tint = Color.White, modifier = Modifier.size(15.dp))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    TextLink(if (p.avatarData == null) "Choose photo" else "Change photo") { pick() }
                    if (p.avatarData != null) TextLink("Remove", Color(0xFFFF453A)) { p = p.copy(avatarData = null) }
                }
            }
            Column { FormHeader("Name"); FormGroup { FormField(p.name, { p = p.copy(name = it) }, "Your name") } }
            Column { FormHeader("Bio"); FormGroup { FormField(p.bio, { p = p.copy(bio = it) }, "A line about your taste", singleLine = false) } }
        }
    }
}

/// A square, centre-cropped 320px JPEG — small enough to keep with the library.
private suspend fun avatarJPEG(ctx: Context, uri: Uri): String? = withContext(Dispatchers.IO) {
    runCatching {
        val img = ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return@runCatching null
        val side = minOf(img.width, img.height)
        val crop = Bitmap.createBitmap(img, (img.width - side) / 2, (img.height - side) / 2, side, side)
        val out = Bitmap.createScaledBitmap(crop, 320, 320, true)
        val bytes = ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        Base64.encodeToString(bytes, Base64.NO_WRAP)
    }.getOrNull()
}

/// Your favourite shows, up to eight: reorder, remove, or add more.
@Composable
fun FavoritesEditor() {
    var adding by rememberSaveable { mutableStateOf(false) }
    if (adding) { FavoritePicker { adding = false }; return }
    val list = Library.favorites
    Column(Modifier.fillMaxSize().background(Theme.bg)) {
        SheetBar("Favourites", trailing = { SaveButton(onClick = LocalDismiss.current) })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormGroup {
                for ((i, f) in list.withIndex()) {
                    if (i > 0) Hairline(Modifier.padding(start = 16.dp))
                    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Filled.RemoveCircle, "Remove", tint = Color(0xFFFF453A), modifier = Modifier.size(24.dp).clickableNoRipple { Library.removeFavorite(f) })
                        PosterView(f, width = 40.dp, corner = 4.dp, glows = false)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(f.title, style = Type.body.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(listOfNotNull(f.category?.label ?: "Show", f.yearText.ifEmpty { null }).joinToString(" · "), style = Type.caption, color = Theme.dim)
                        }
                        Icon(Icons.Filled.KeyboardArrowUp, "Move up", tint = if (i > 0) Color.White else Theme.dim, modifier = Modifier.size(28.dp).clickableNoRipple(i > 0) { Library.moveFavorite(i, i - 1) })
                        Icon(Icons.Filled.KeyboardArrowDown, "Move down", tint = if (i < list.lastIndex) Color.White else Theme.dim,
                            modifier = Modifier.size(28.dp).clickableNoRipple(i < list.lastIndex) { Library.moveFavorite(i, i + 1) })
                    }
                }
                if (!Library.favoritesFull) {
                    if (list.isNotEmpty()) Hairline(Modifier.padding(start = 16.dp))
                    Row(Modifier.fillMaxWidth().clickable { adding = true }.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Filled.Add, null, tint = Theme.accent)
                        Text("Add a show", style = Type.body, color = Theme.accent)
                    }
                }
            }
            FormFooter(if (list.isEmpty()) "Pick up to ${LibraryDoc.MAX_FAVORITES} shows to show on your profile."
            else "${list.size} of ${LibraryDoc.MAX_FAVORITES}. Use the arrows to reorder — they show on your profile in this order.")
        }
    }
}

/// Search for a show to add to your favourites.
@Composable
private fun FavoritePicker(onDone: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<List<FilmRef>>(emptyList()) }
    LaunchedEffect(query) {
        if (query.isBlank()) { results = emptyList(); return@LaunchedEffect }
        kotlinx.coroutines.delay(300)
        runCatching { Catalog.search(query) }.onSuccess { results = it }
    }
    /// Before you search: shows you're watching or have finished.
    val yours = (Library.currentlyWatching + Library.showsInProgress + Library.watchedFilms).distinctBy { it.id }
    val pool = (if (query.isBlank()) yours else results).filter { !Library.isFavorite(it.id) }
    Column(Modifier.fillMaxSize().background(Theme.bg)) {
        SheetBar("Add a favourite", leading = { IconCircle(Icons.AutoMirrored.Filled.ArrowBack, "Back", 34.dp, Theme.chip, onClick = onDone) })
        SearchField(query, { query = it }, "Search shows", Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
            if (pool.isEmpty()) EmptyState(Icons.Filled.Search, if (query.isBlank()) "Search for a show" else "No matches", "Pick the ones you'd watch again and again.", Modifier.padding(top = 40.dp))
            for (row in pool.chunked(4)) {
                Row(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (f in row) Box(Modifier.weight(1f).clickableNoRipple { Library.addFavorite(f); onDone() }) { PosterView(f, corner = 6.dp) }
                    repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

// MARK: - The moving colour card

/// A slowly moving blend in the spirit of the Apple Card in Wallet: big soft blobs of colour that
/// drift, cycle through every colour of your favourites, and lean as you tilt the phone.
object FavoritesMesh {
    val fallback = listOf(Theme.accent, Theme.heart, Color(0.55f, 0.35f, 1f), Theme.star, Theme.list)
}

@Composable
fun FavoritesMesh(colors: List<Color>, modifier: Modifier = Modifier) {
    val pal = colors.ifEmpty { FavoritesMesh.fallback }
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) { while (true) withInfiniteAnimationFrameMillis { t = it / 1000f } }
    val tilt = rememberTilt()
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        drawRect(Color.Black)
        // A 4×4 grid of points; interior ones wander in loops, and each fades between palette colours on its own clock.
        for (y in 0 until 4) for (x in 0 until 4) {
            val seed = (x * 7 + y * 13).toFloat()
            var px = x / 3f
            var py = y / 3f
            if (x in 1..2) px += 0.13f * sin(t * (0.42f + seed * 0.011f) + seed) + tilt.first * 0.08f
            if (y in 1..2) py += 0.13f * cos(t * (0.37f + seed * 0.013f) + seed * 0.7f) + tilt.second * 0.08f
            val i = y * 4 + x
            val phase = t * 0.09f + i * 0.61f
            val k = kotlin.math.floor(phase).toInt()
            val f = phase - k
            val smooth = f * f * (3 - 2 * f)
            val n = pal.size
            val a = pal[((k + i * 3) % n + n) % n]
            val b = pal[((k + 1 + i * 3) % n + n) % n]
            val c = lerp(a, b, smooth)
            val center = Offset(px * w, py * h)
            val r = max(w, h) * 0.42f
            drawCircle(Brush.radialGradient(0f to c, 0.45f to c.copy(alpha = 0.75f), 1f to c.copy(alpha = 0f), center = center, radius = r), r, center)
        }
        drawRect(Color.Black.copy(alpha = 0.18f))
        // Fade into black below the middle.
        drawRect(Brush.verticalGradient(0f to Color.Transparent, 0.5f to Color.Transparent, 1f to Color.Black))
    }
}

/// Gentle device tilt for parallax, smoothed. No permission needed.
@Composable
fun rememberTilt(): Pair<Float, Float> {
    val ctx = LocalContext.current
    var tilt by remember { mutableStateOf(0f to 0f) }
    DisposableEffect(Unit) {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = sm.getDefaultSensor(Sensor.TYPE_GRAVITY)
        val listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val gx = (-e.values[0] / 9.81f).coerceIn(-1f, 1f)
                val gy = (e.values[1] / 9.81f - 0.6f).coerceIn(-1f, 1f) * -1f
                tilt = (tilt.first + (gx - tilt.first) * 0.12f) to (tilt.second + (gy - tilt.second) * 0.12f)
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        if (sensor != null) sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        onDispose { sm.unregisterListener(listener) }
    }
    return tilt
}
