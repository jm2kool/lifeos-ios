package com.jm2kool.matinee.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.FilmArt
import com.jm2kool.matinee.data.TMDB
import com.jm2kool.matinee.data.Taste
import com.jm2kool.matinee.data.largePoster
import com.jm2kool.matinee.model.FilmDetail
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Persona
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.Toast
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/// A Tinder-style stack of full-screen show cards. Drag or tap the buttons to swipe.
@Composable
fun SwipeDeck(
    films: List<FilmRef>,
    modifier: Modifier = Modifier,
    likeLabel: String = "LOVE",
    nopeLabel: String = "NOPE",
    likeIcon: ImageVector = Icons.Filled.Favorite,
    likeColor: Color = Theme.heart,
    middle: Pair<ImageVector, String>? = null,
    onSwipe: (FilmRef, Boolean) -> Unit,
    onMiddle: ((FilmRef) -> Unit)? = null,
    onTap: ((FilmRef) -> Unit)? = null,
    onTop: ((FilmRef?) -> Unit)? = null,
    empty: @Composable () -> Unit,
) {
    var index by remember { mutableIntStateOf(0) }
    val drag = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    val scope = rememberCoroutineScope()
    val d = LocalDensity.current
    val far = with(d) { 700.dp.toPx() }
    LaunchedEffect(index, films.size) { onTop?.invoke(films.getOrNull(index)) }

    fun advance(direction: Int) {
        scope.launch {
            val target = if (direction == 0) Offset(0f, -far * 1.3f) else Offset(direction * far, drag.value.y + with(d) { 40.dp.toPx() })
            drag.animateTo(target, tween(220, easing = FastOutLinearInEasing))
            index += 1
            drag.snapTo(Offset.Zero)
        }
    }
    fun swipe(f: FilmRef, right: Boolean) {
        if (right) Haptics.medium() else Haptics.light()
        onSwipe(f, right)
        advance(if (right) 1 else -1)
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (index >= films.size) empty()
            else {
                val visible = films.withIndex().filter { it.index >= index && it.index < index + 3 }.reversed()
                for ((i, f) in visible) key(f.id) {
                    val depth = i - index
                    val top = depth == 0
                    val scale by animateFloatAsState(1f - depth * 0.05f, label = "scale")
                    val dy by animateFloatAsState(depth * 14f, label = "dy")
                    DeckCard(
                        f, likeLabel, nopeLabel, likeColor, lean = if (top) with(d) { drag.value.x.toDp() }.value else 0f,
                        modifier = Modifier.fillMaxSize().zIndex(-depth.toFloat())
                            .graphicsLayer {
                                scaleX = scale; scaleY = scale
                                translationY = dy * density + if (top) drag.value.y else 0f
                                translationX = if (top) drag.value.x else 0f
                                rotationZ = if (top) drag.value.x / density / 22f else 0f
                                transformOrigin = TransformOrigin(0.5f, 1f)
                            }
                            .then(if (!top) Modifier else Modifier
                                .pointerInput(f.id) { detectTapGestures { onTap?.invoke(f) } }
                                .pointerInput(f.id) {
                                    val tracker = VelocityTracker()
                                    detectDragGestures(
                                        onDragStart = { tracker.resetTracking() },
                                        onDragEnd = {
                                            val v = tracker.calculateVelocity()
                                            val x = drag.value.x
                                            val predicted = x + v.x * 0.25f
                                            val dist = with(d) { 110.dp.toPx() }
                                            if (abs(x) > dist || abs(predicted) > with(d) { 380.dp.toPx() }) {
                                                swipe(f, (if (abs(predicted) > abs(x)) predicted else x) > 0)
                                            } else scope.launch { drag.animateTo(Offset.Zero, spring(0.7f, Spring.StiffnessMediumLow)) }
                                        },
                                        onDragCancel = { scope.launch { drag.animateTo(Offset.Zero) } },
                                    ) { change, amount ->
                                        change.consume()
                                        tracker.addPosition(change.uptimeMillis, change.position)
                                        scope.launch { drag.snapTo(drag.value + amount) }
                                    }
                                }),
                    )
                }
            }
        }
        if (index < films.size) {
            Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
                RoundButton(Icons.Filled.Close, 62.dp, Color.White, nopeLabel) { films.getOrNull(index)?.let { swipe(it, false) } }
                if (middle != null) RoundButton(middle.first, 50.dp, Color.White.copy(alpha = 0.85f), middle.second) {
                    films.getOrNull(index)?.let { onMiddle?.invoke(it); advance(0) }
                }
                RoundButton(likeIcon, 62.dp, likeColor, likeLabel) { films.getOrNull(index)?.let { swipe(it, true) } }
            }
        }
    }
}

@Composable
fun RoundButton(icon: ImageVector, size: Dp, color: Color, description: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(Modifier.size(size).clip(CircleShape).background(Color.White.copy(alpha = 0.14f)).border(0.5.dp, Theme.line, CircleShape)
        .clickable(enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, description, tint = color, modifier = Modifier.size(size * 0.4f))
    }
}

/// One card: the textless poster edge to edge, the show's logo, and stamps as you drag.
@Composable
fun DeckCard(film: FilmRef, likeLabel: String, nopeLabel: String, likeColor: Color, lean: Float, modifier: Modifier = Modifier, expanded: Boolean = false) {
    var art by remember(film.id) { mutableStateOf<FilmArt?>(null) }
    var artLoaded by remember(film.id) { mutableStateOf(false) }
    var detail by remember(film.id) { mutableStateOf<FilmDetail?>(null) }
    LaunchedEffect(film.id) {
        art = Catalog.art(film.id); artLoaded = true
        detail = runCatching { Catalog.detail(film.id) }.getOrNull()
    }
    val corner = if (expanded) 0.dp else 32.dp
    val shape = RoundedCornerShape(corner)
    Box(modifier.softShadow(20.dp, 10.dp, corner, 0.5f).clip(shape).background(Theme.card).border(0.5.dp, Theme.line, shape)) {
        RemoteImage(art?.poster ?: film.largePoster ?: film.poster, Modifier.fillMaxSize())
        if (!expanded) {
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.45f to Color.Transparent, 0.8f to Color.Black.copy(alpha = 0.75f), 1f to Color.Black.copy(alpha = 0.95f))))
            Column(Modifier.align(Alignment.BottomCenter).padding(horizontal = 20.dp).padding(bottom = 26.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TitleArt(film.title, art?.logo, aspect = art?.logoAspect ?: 3.0, maxWidth = 240.dp, maxHeight = 90.dp, fontSize = 32f, ready = artLoaded)
                val n = detail?.regularSeasons?.size ?: 0
                Text(listOfNotNull(film.yearText.ifEmpty { null }, detail?.genres?.take(2)?.joinToString(", ")?.ifEmpty { null },
                    if (n > 0) (if (n == 1) "1 season" else "$n seasons") else null).joinToString(" · "),
                    style = Type.subheadline.semibold(), color = Color.White.copy(alpha = 0.8f), maxLines = 1, textAlign = TextAlign.Center)
            }
            Stamp(likeLabel, likeColor, -14f, Modifier.align(Alignment.TopStart).padding(26.dp).graphicsLayer { alpha = (lean / 90f).coerceIn(0f, 1f) })
            Stamp(nopeLabel, Color.White, 14f, Modifier.align(Alignment.TopEnd).padding(26.dp).graphicsLayer { alpha = (-lean / 90f).coerceIn(0f, 1f) })
        }
    }
}

@Composable
private fun Stamp(text: String, color: Color, angle: Float, modifier: Modifier) {
    Text(text, color = color, style = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.ExtraBold),
        modifier = modifier.rotate(angle).border(4.dp, color, RoundedCornerShape(10.dp)).padding(horizontal = 14.dp, vertical = 4.dp))
}

// MARK: - Taste quiz

/// Drives the endless quiz: explores every genre first, then narrows in on your favourites
/// until your character is clear.
class QuizEngine {
    val cards = mutableStateListOf<Pair<FilmRef, List<String>>>()
    private val exposure = HashMap<String, Double>()
    var decisive by mutableIntStateOf(0); private set
    var likes by mutableIntStateOf(0); private set
    var failed by mutableStateOf(false); private set
    var version by mutableIntStateOf(0); private set
    private val topHistory = ArrayList<List<String>>()
    private val seen = HashSet<String>()
    private val pages = HashMap<String, Int>()
    private var loading = false
    private var rotation = 0

    companion object {
        val genres get() = Catalog.genreNames
        val main = setOf("Romance", "Comedy", "Melodrama", "Mystery", "Crime", "Fantasy")
        fun required(g: String) = if (g in main) 2.0 else 1.0
        fun top(scores: Map<String, Double>, n: Int) = scores.filter { it.value > 0 }.entries.sortedByDescending { it.value }.take(n).map { it.key }
    }

    private fun need(g: String) = max(0.0, required(g) - (exposure[g] ?: 0.0))
    private val uncovered get() = genres.filter { need(it) > 0 }

    suspend fun start() {
        cards.clear(); exposure.clear(); decisive = 0; likes = 0; topHistory.clear(); seen.clear(); pages.clear(); failed = false
        runCatching { TMDB.deck() }.getOrNull()?.take(14)?.forEach { if (seen.add(it.first.id)) cards.add(it) }
        if (cards.isEmpty()) topUp()
        if (cards.isEmpty()) failed = true
    }

    /// Record a swipe. `liked == null` means "haven't seen".
    fun record(film: FilmRef, liked: Boolean?, scores: Map<String, Double>) {
        val idx = cards.indexOfFirst { it.first.id == film.id }
        if (idx < 0) return
        for (g in cards[idx].second) exposure[g] = (exposure[g] ?: 0.0) + if (liked == null) 0.5 else 1.0
        if (liked != null) {
            decisive++
            if (liked) likes++
            topHistory.add(top(scores, 2))
        }
        version++
        reprioritize(idx)
    }

    fun needsMore(idx: Int) = cards.size - idx - 1 < 8

    private fun separation(scores: Map<String, Double>): Double {
        val v = scores.values.sortedDescending()
        val first = v.firstOrNull() ?: 0.0
        val third = v.getOrNull(2) ?: 0.0
        return ((first - third) / 3).coerceIn(0.0, 1.0)
    }

    private val stable: Boolean
        get() {
            if (topHistory.size < 6) return false
            val last = topHistory.takeLast(6).map { it.toSet() }
            return last.all { it == last.last() && it.size == 2 }
        }

    fun confidence(scores: Map<String, Double>): Double {
        val total = genres.sumOf { required(it) }
        val covered = genres.sumOf { min(required(it), exposure[it] ?: 0.0) }
        val coverage = covered / total
        val stability = if (stable) 1.0 else min(topHistory.size, 6) / 6.0 * 0.6
        val raw = 0.45 * coverage + 0.35 * separation(scores) + 0.2 * stability
        return if (isSure(scores)) 1.0 else min(0.97, raw)
    }

    fun isSure(scores: Map<String, Double>) = uncovered.isEmpty() && separation(scores) >= 0.66 && stable && likes >= 5 && decisive >= 15

    val phase: String
        get() = if (uncovered.isNotEmpty()) "Exploring genres · ${genres.size - uncovered.size} of ${genres.size}" else "Narrowing in on your taste"

    /// Cards beyond the visible stack get re-ordered so the most useful ones come next.
    private fun reprioritize(idx: Int) {
        val keep = idx + 4   // leave the cards already stacked on screen alone
        if (cards.size <= keep + 1) return
        val tail = cards.subList(keep, cards.size).toList()
        val exploring = uncovered.isNotEmpty()
        val leaders = (topHistory.lastOrNull() ?: emptyList()).toSet()
        val sorted = tail.map { c ->
            val s = if (exploring) c.second.sumOf { need(it) } else c.second.sumOf { if (it in leaders) 1.0 else 0.1 }
            c to s + Random.nextDouble(0.0, 0.3)
        }.sortedByDescending { it.second }.map { it.first }
        for (i in sorted.indices) cards[keep + i] = sorted[i]
    }

    suspend fun topUp() {
        if (loading) return
        loading = true
        try {
            repeat(3) {
                val target = nextTarget()
                val page = (pages[target] ?: 0) + 1
                pages[target] = page
                val fresh = TMDB.deckPage(target, page).filter { seen.add(it.first.id) }
                if (fresh.isNotEmpty()) { cards.addAll(fresh.shuffled().take(10)); return }
            }
        } finally { loading = false }
    }

    private fun nextTarget(): String {
        // Still exploring: go to the genre we know least about.
        uncovered.shuffled().maxByOrNull { need(it) }?.let { return it }
        val leaders = topHistory.lastOrNull() ?: emptyList()
        rotation++
        return when (rotation % 5) {
            1, 3 -> leaders.firstOrNull() ?: genres.random()
            2 -> leaders.getOrNull(1) ?: genres.random()
            else -> genres.random()          // keep re-testing the rest
        }
    }
}

/// Swipe through dramas — as many as it takes — to build your drama character.
@Composable
fun TasteQuizView(onClose: () -> Unit) {
    val engine = remember { QuizEngine() }
    var result by remember { mutableStateOf<Persona?>(null) }
    var top by remember { mutableStateOf<FilmRef?>(null) }
    var swiped by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { Taste.beginQuiz(); engine.start() }
    DisposableEffect(Unit) { onDispose { if (result == null) Taste.abandonQuiz() } }
    androidx.activity.compose.BackHandler { Taste.skipQuiz(); onClose() }

    fun reveal() {
        if (result != null) return
        Haptics.success()
        result = Taste.finish()
        scope.launch { runCatching { Taste.refreshPicks(force = true) } }
    }

    Box(Modifier.fillMaxSize().background(Color.Black).clickableNoRipple { }) {
        AmbientGlow(if (result == null) listOfNotNull(top?.poster) else emptyList(), 0.55f)
        AnimatedContent(result, transitionSpec = { (fadeIn(tween(500)) + scaleIn(initialScale = 0.9f)) togetherWith fadeOut(tween(300)) }, label = "quiz") { r ->
            if (r != null) PersonaReveal(r, onClose)
            else Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                val confidence = engine.confidence(Taste.profile.scores).let { engine.version; it }
                Column(Modifier.padding(horizontal = 20.dp).padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.fillMaxWidth()) {
                        BarButton("Skip", Theme.dim, bold = true) { Taste.skipQuiz(); onClose() }
                        Spacer(Modifier.weight(1f))
                        if (engine.decisive >= 40) BarButton("Finish now", Theme.accent, bold = true) { reveal() }
                    }
                    Text("What's your drama character?", style = Type.title2.heavy(), color = Color.White, textAlign = TextAlign.Center)
                    Text("Swipe right on dramas you love, left on ones that aren't for you. We'll keep going until we really know you.",
                        style = Type.subheadline, color = Theme.dim, textAlign = TextAlign.Center)
                    Column(Modifier.padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        LinearProgressIndicator(progress = { confidence.toFloat() }, color = Theme.accent, trackColor = Color.White.copy(alpha = 0.15f),
                            drawStopIndicator = {}, gapSize = 0.dp, modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape))
                        Row {
                            Text(engine.phase, style = Type.caption.semibold(), color = Theme.dim, modifier = Modifier.weight(1f))
                            Text("${(confidence * 100).toInt()}% sure", style = Type.caption.semibold(), color = Theme.dim)
                        }
                    }
                }
                if (engine.cards.isEmpty()) {
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        if (engine.failed) EmptyState(Icons.Filled.WifiOff, "Couldn't load dramas", "Check your connection and try again.")
                        else CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                    }
                } else {
                    SwipeDeck(
                        engine.cards.map { it.first }, Modifier.weight(1f).padding(horizontal = 16.dp),
                        middle = Icons.Filled.VisibilityOff to "Haven't seen",
                        onSwipe = { f, liked ->
                            Taste.record(f, engine.cards.firstOrNull { it.first.id == f.id }?.second ?: emptyList(), liked)
                            engine.record(f, liked, Taste.profile.scores)
                            swiped++
                            if (engine.needsMore(swiped)) scope.launch { engine.topUp() }
                            if (engine.isSure(Taste.profile.scores)) reveal()
                        },
                        onMiddle = { f -> engine.record(f, null, Taste.profile.scores); swiped++; if (engine.needsMore(swiped)) scope.launch { engine.topUp() } },
                        onTop = { top = it },
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(26.dp))
                            Text("Finding more dramas…", style = Type.subheadline, color = Theme.dim)
                            LaunchedEffect(Unit) { engine.topUp() }
                        }
                    }
                }
            }
        }
    }
}

/// The big reveal: your drama character.
@Composable
fun PersonaReveal(persona: Persona, onDone: () -> Unit) {
    val shown = remember { Animatable(0f) }
    LaunchedEffect(Unit) { delay(100); shown.animateTo(1f, spring(0.6f, Spring.StiffnessLow)) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().navigationBarsPadding().padding(24.dp)
        .graphicsLayer { alpha = shown.value.coerceIn(0f, 1f) }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Text(persona.emoji, fontSize = 96.sp, modifier = Modifier.padding(top = 40.dp).graphicsLayer {
            val s = 0.3f + 0.7f * shown.value; scaleX = s; scaleY = s; rotationZ = (1 - shown.value) * -30f
        })
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("YOU'RE", style = Type.caption.heavy().tracking(2f), color = Theme.dim)
            Text(persona.name, style = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.ExtraBold, fontSize = 34.sp, lineHeight = 40.sp), color = Color.White, textAlign = TextAlign.Center)
        }
        Text(persona.blurb, style = Type.body, color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp))
        PersonaCard(persona, compact = false)
        PillButton("Start exploring", prominent = true, size = ControlSize.LARGE, fill = true, onClick = onDone)
    }
}

// MARK: - Lists as a swipe deck

enum class DeckAction { WATCHLIST, TONIGHT, LIKE }

/// Any list, opened full screen as a swipe deck. The toolbar button flips to the normal view.
@Composable
fun FilmDeckScreen(films: List<FilmRef>, action: DeckAction) {
    var rightCount by remember { mutableIntStateOf(0) }
    var round by remember { mutableIntStateOf(0) }
    var top by remember { mutableStateOf<FilmRef?>(null) }
    val (like, nope, icon, color) = when (action) {
        DeckAction.WATCHLIST -> Quad("WANT", "SKIP", Icons.Filled.Schedule, Theme.list)
        DeckAction.TONIGHT -> Quad("TONIGHT", "LATER", Icons.Filled.PlayArrow, Theme.accent)
        DeckAction.LIKE -> Quad("LOVE", "MEH", Icons.Filled.Favorite, Theme.heart)
    }
    val summary = when (action) {
        DeckAction.WATCHLIST -> if (rightCount == 0) "Nothing caught your eye this time." else "$rightCount added to your watchlist."
        DeckAction.TONIGHT -> "Nothing tonight? Your watchlist will be here."
        DeckAction.LIKE -> if (rightCount == 0) "No new likes this round." else "$rightCount more shows liked."
    }
    Box(Modifier.fillMaxSize()) {
        AmbientGlow(listOfNotNull(top?.poster), 0.55f)
        key(round) {
            SwipeDeck(
                films, Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 12.dp).navigationBarsPadding(),
                likeLabel = like, nopeLabel = nope, likeIcon = icon, likeColor = color,
                onSwipe = { f, right ->
                    if (!right) return@SwipeDeck
                    rightCount++
                    when (action) {
                        DeckAction.WATCHLIST -> if (!Library.inWatchlist(f.id)) Library.toggleWatchlist(f) else Library.toast = Toast("Already in your watchlist", Icons.Filled.Schedule)
                        DeckAction.LIKE -> if (!Library.isLiked(f.id)) Library.toggleLike(f)
                        DeckAction.TONIGHT -> {
                            // Tonight's the night: pin it to Currently watching and open it at the next episode.
                            if (!Library.isCurrentlyWatching(f.id)) Library.toggleCurrentlyWatching(f)
                            Router.open(f)
                        }
                    }
                },
                onTap = { Router.open(it) },
                onTop = { top = it },
            ) {
                Column(Modifier.padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("🍿", fontSize = 64.sp)
                    Text("That's all ${films.size}", style = Type.title2, color = Color.White)
                    Text(summary, style = Type.subheadline, color = Theme.dim, textAlign = TextAlign.Center)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        PillButton("Go again", size = ControlSize.LARGE) { round++; rightCount = 0 }
                        PillButton("Show as list", prominent = true, size = ControlSize.LARGE) { Prefs.putDeckMode(false) }
                    }
                }
            }
        }
    }
}

private data class Quad(val a: String, val b: String, val c: ImageVector, val d: Color)

@Suppress("unused")
private fun BoxScope.unused() = Unit
