package com.jm2kool.matinee.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import android.graphics.Paint
import android.util.Base64
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.automirrored.filled.StarHalf
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.HeartBroken
import androidx.compose.material.icons.outlined.TimerOff
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.Images
import com.jm2kool.matinee.data.Palette
import com.jm2kool.matinee.model.DramaFilter
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.Profile
import com.jm2kool.matinee.model.RatingStyle
import com.jm2kool.matinee.model.Score
import com.jm2kool.matinee.model.Stars
import com.jm2kool.matinee.model.Toast
import com.jm2kool.matinee.ui.Type.bold
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

// MARK: - Images

@Composable
fun RemoteImage(url: String?, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Crop) {
    Box(modifier.background(Theme.card)) {
        if (url != null) {
            val ctx = androidx.compose.ui.platform.LocalContext.current
            AsyncImage(
                model = remember(url) { ImageRequest.Builder(ctx).data(url).crossfade(250).build() },
                imageLoader = Images.loader,
                contentDescription = null,
                contentScale = contentScale,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/// A poster with 2:3 proportions that casts a soft halo in its own colour. Fetches its own artwork if the ref has none.
@Composable
fun PosterView(
    film: FilmRef,
    modifier: Modifier = Modifier,
    width: Dp? = null,
    corner: Dp = 8.dp,
    showTitleFallback: Boolean = true,
    glows: Boolean = true,
) {
    var fetched by remember(film.id) { mutableStateOf<String?>(null) }
    var glow by remember { mutableStateOf<Color?>(null) }
    val url = film.poster ?: fetched
    LaunchedEffect(url, glows) {
        if (!glows || url == null) return@LaunchedEffect
        glow = (Palette.cached(url) ?: Palette.of(url))?.glow
    }
    LaunchedEffect(film.id) {
        if (film.poster != null) return@LaunchedEffect
        runCatching { Catalog.detail(film.id) }.getOrNull()?.let { fetched = it.ref.poster; Library.hydrate(film, it) }
    }
    val g by animateColorAsState(glow ?: Color.Transparent, tween(500), label = "glow")
    val w = width ?: 90.dp
    val shape = RoundedCornerShape(corner)
    Box(
        (if (width != null) modifier.width(width) else modifier.fillMaxWidth())
            .aspectRatio(2f / 3f)
            .glow(g, radius = max(6f, w.value * 0.14f).dp, offsetY = max(2f, w.value * 0.05f).dp, corner = corner)
            .clip(shape)
            .background(Theme.card)
            .border(0.5.dp, Theme.line, shape),
        contentAlignment = Alignment.Center,
    ) {
        if (url == null && showTitleFallback) {
            Text(film.title, style = Type.caption2.semibold(), color = Color.White.copy(alpha = 0.6f), textAlign = TextAlign.Center, modifier = Modifier.padding(6.dp))
        }
        if (url != null) RemoteImage(url, Modifier.fillMaxSize())
    }
}

/// Tap to open, long-press for quick actions — the fastest way to log, like or save.
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FilmMenuBox(film: FilmRef, modifier: Modifier = Modifier, onClick: () -> Unit = { Router.open(film) }, content: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(modifier.combinedClickable(
        interactionSource = remember { MutableInteractionSource() }, indication = null,
        onClick = onClick, onLongClick = { Haptics.heavy(); open = true },
    )) {
        content()
        FilmMenu(film, open) { open = false }
    }
}

@Composable
fun FilmMenu(film: FilmRef, expanded: Boolean, onDismiss: () -> Unit) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss, containerColor = Color(0xFF1C1C1E)) {
        val watched = Library.isWatched(film.id)
        val liked = Library.isLiked(film.id)
        val saved = Library.inWatchlist(film.id)
        MenuItem("Log or review…", Icons.Filled.AddCircleOutline) { onDismiss(); Router.sheet = SheetRoute.Log(film, null) }
        MenuItem(if (watched) "Remove from watched" else "Mark as watched", if (watched) Icons.Outlined.VisibilityOff else Icons.Filled.Visibility) { onDismiss(); Library.toggleWatched(film) }
        MenuItem(if (liked) "Unlike" else "Like", if (liked) Icons.Outlined.HeartBroken else Icons.Filled.FavoriteBorder) { onDismiss(); Library.toggleLike(film) }
        MenuItem(if (saved) "Remove from watchlist" else "Add to watchlist", if (saved) Icons.Outlined.TimerOff else Icons.Filled.Schedule) { onDismiss(); Library.toggleWatchlist(film) }
        MenuItem("Add to list…", Icons.AutoMirrored.Filled.PlaylistAdd) { onDismiss(); Router.sheet = SheetRoute.AddToList(film) }
    }
}

@Composable
fun MenuItem(text: String, icon: ImageVector?, destructive: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    val c = if (destructive) Color(0xFFFF453A) else Color.White
    DropdownMenuItem(
        text = { Text(text, style = Type.body, color = if (enabled) c else c.copy(alpha = 0.4f)) },
        trailingIcon = icon?.let { { Icon(it, null, tint = if (enabled) c else c.copy(alpha = 0.4f)) } },
        onClick = onClick, enabled = enabled,
    )
}

// MARK: - Stars

/// Tap or drag across the stars to rate in half steps; tap the current rating again to clear it.
@Composable
fun StarRating(rating: Double?, size: Dp = 34.dp, spacing: Dp = 6.dp, onChange: ((Double?) -> Unit)? = null) {
    var dragValue by remember { mutableStateOf<Double?>(null) }
    val shown = dragValue ?: rating ?: 0.0
    val d = LocalDensity.current
    val total = with(d) { (size * 5 + spacing * 4).toPx() }
    fun value(x: Float): Double {
        val raw = (x.coerceIn(0f, total) / total) * 5.0
        return max(0.5, min(5.0, ceil(raw * 2) / 2))
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(spacing),
        modifier = if (onChange == null) Modifier else Modifier.pointerInput(rating) {
            awaitEachGesture {
                val down = awaitFirstDown()
                var v = value(down.position.x)
                dragValue = v; Haptics.selection()
                var moved = 0f
                while (true) {
                    val e = awaitPointerEvent()
                    val c = e.changes.firstOrNull() ?: break
                    if (!c.pressed) break
                    moved = max(moved, abs(c.position.x - down.position.x))
                    val n = value(c.position.x)
                    if (n != v) { v = n; dragValue = n; Haptics.selection() }
                    c.consume()
                }
                dragValue = null
                if (moved < 4 * density && v == rating) onChange(null) else onChange(v)
                Haptics.light()
            }
        },
    ) {
        for (i in 1..5) {
            val v = shown - (i - 1)
            val icon = if (v >= 1) Icons.Filled.Star else if (v >= 0.5) Icons.AutoMirrored.Filled.StarHalf else Icons.Filled.StarBorder
            val scale by animateFloatAsState(if (dragValue != null && ceil(shown).toInt() == i) 1.15f else 1f, label = "star")
            Icon(icon, null, tint = if (v >= 0.5) Theme.star else Color.White.copy(alpha = 0.22f), modifier = Modifier.size(size).scale(scale))
        }
    }
}

@Composable
fun SmallStars(rating: Double?) {
    if (rating != null && rating > 0) Text(Stars.text(rating), style = Type.caption.semibold(), color = Theme.star)
}

// MARK: - Scores (1–100)

object ScoreColors {
    /// Red for a miss, through marquee orange and amber, to green and mint for the best.
    val stops = listOf(Color(0.95f, 0.27f, 0.32f), Theme.accent, Theme.star, Theme.watch, Color(0.36f, 0.9f, 0.86f))
    fun color(s: Double): Color = when {
        s < 40 -> stops[0]
        s < 60 -> stops[1]
        s < 75 -> stops[2]
        s < 90 -> stops[3]
        else -> stops[4]
    }
}

/// Rate a show out of 100 by dragging round the dial. Every point ticks under your thumb, every ten
/// clicks harder; − and + nudge by one. Tap the number to clear it.
@Composable
fun ScoreDial(score: Double?, size: Dp = 200.dp, onChange: ((Double?) -> Unit)? = null) {
    var dragValue by remember { mutableStateOf<Double?>(null) }
    val shown = dragValue ?: score
    val sweep = 270.0
    val start = 135.0     // degrees, clockwise from 3 o'clock: the arc opens at the bottom
    val line = size * 0.075f
    val anim by animateFloatAsState(((shown ?: 1.0) - 1).toFloat() / 99f, if (dragValue == null) tween(300) else tween(0), label = "dial")
    val d = LocalDensity.current
    val sizePx = with(d) { size.toPx() }

    fun isCentre(p: Offset) = hypot(p.x - sizePx / 2, p.y - sizePx / 2) < sizePx * 0.28f
    /// Angle of the touch round the dial → 1…100. Touches in the gap at the bottom stick to the nearer end.
    fun value(p: Offset): Double {
        val deg = atan2((p.y - sizePx / 2).toDouble(), (p.x - sizePx / 2).toDouble()) * 180 / PI
        var rel = deg - start
        while (rel < 0) rel += 360
        while (rel >= 360) rel -= 360
        val f = if (rel <= sweep) rel / sweep else if (rel < sweep + (360 - sweep) / 2) 1.0 else 0.0
        return (1 + f * 99).roundToInt().toDouble()
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(size).then(if (onChange == null) Modifier else Modifier.pointerInput(score) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    val startedCentre = isCentre(down.position)
                    var moved = false
                    var last: Double? = null
                    if (!startedCentre) { last = value(down.position); dragValue = last; Haptics.selection() }
                    while (true) {
                        val e = awaitPointerEvent()
                        val c = e.changes.firstOrNull() ?: break
                        if (!c.pressed) {
                            if (!moved && startedCentre && isCentre(c.position)) {
                                // A tap on the number clears the score; it never rates.
                                dragValue = null
                                if (score != null) { onChange(null); Haptics.light() }
                                return@awaitEachGesture
                            }
                            break
                        }
                        if ((c.position - down.position).getDistance() > 4 * density) moved = true
                        if (moved || !startedCentre) {
                            val v = value(c.position)
                            if (v != last) {
                                val old = last
                                if (old != null && old.toInt() / 10 != v.toInt() / 10) Haptics.medium() else Haptics.selection()
                                last = v; dragValue = v
                            }
                        }
                        c.consume()
                    }
                    dragValue = null
                    last?.let { onChange(it); Haptics.light() }
                }
            }),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val pad = line.toPx() * 1.9f
                val stroke = line.toPx()
                val r = (this.size.minDimension - pad * 2) / 2
                val c = Offset(this.size.width / 2, this.size.height / 2)
                val tl = Offset(c.x - r, c.y - r)
                val arcSize = Size(r * 2, r * 2)
                // Ticks round the outside.
                for (i in 0..10) {
                    val a = Math.toRadians(start + sweep * i / 10).toFloat()
                    val lit = (shown ?: 0.0) >= max(1, i * 10).toDouble()
                    val len = if (i % 5 == 0) stroke * 0.9f else stroke * 0.55f
                    val dist = r + stroke * 1.3f
                    val p = Offset(c.x + cos(a) * dist, c.y + sin(a) * dist)
                    val dir = Offset(cos(a), sin(a))
                    drawLine(if (lit) ScoreColors.color(i * 10.0) else Color.White.copy(alpha = 0.18f),
                        p - dir * (len / 2), p + dir * (len / 2), strokeWidth = 2.dp.toPx(), cap = StrokeCap.Round)
                }
                drawArc(Color.White.copy(alpha = 0.1f), start.toFloat(), sweep.toFloat(), false, tl, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
                if (shown != null) {
                    val frac = max(0.004f, anim)
                    val stops = ScoreColors.stops.mapIndexed { i, col -> (i / (ScoreColors.stops.size - 1f)) * 0.75f to col }.toTypedArray()
                    // The glow under the arc.
                    drawArc(ScoreColors.color(shown).copy(alpha = 0.22f), start.toFloat(), (sweep * frac).toFloat(), false,
                        tl, arcSize, style = Stroke(stroke * 2.2f, cap = StrokeCap.Round))
                    rotate(start.toFloat(), c) {
                        drawArc(Brush.sweepGradient(*stops, center = c), 0f, (sweep * frac).toFloat(), false, tl, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
                    }
                    val a = Math.toRadians(start + sweep * frac).toFloat()
                    val kp = Offset(c.x + cos(a) * r, c.y + sin(a) * r)
                    val kr = stroke * 0.75f * (if (dragValue != null) 1.25f else 1f)
                    drawCircle(Color.Black.copy(alpha = 0.3f), kr * 1.15f, kp + Offset(0f, 1.dp.toPx()))
                    drawCircle(Color.White, kr, kp)
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                if (shown != null) {
                    Text(shown.toInt().toString(), color = Color.White, style = TextStyle(fontSize = (size.value * 0.3f).sp, fontWeight = FontWeight.Bold, lineHeight = (size.value * 0.32f).sp))
                    Text("/ 100", color = Color.White.copy(alpha = 0.5f), style = TextStyle(fontSize = (size.value * 0.065f).sp, fontWeight = FontWeight.SemiBold))
                } else {
                    Icon(Icons.Filled.TouchApp, null, tint = Color.White.copy(alpha = 0.4f), modifier = Modifier.size(size * 0.16f))
                    Text("RATE", color = Color.White.copy(alpha = 0.45f), style = TextStyle(fontSize = (size.value * 0.065f).sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.5.sp), modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
        if (onChange != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.offset(y = -size * 0.16f)) {
                Nudge(Icons.Filled.Remove) { onChange(min(100.0, max(1.0, (score ?: 50.0) - 1))) }
                Text(shown?.let(Score::word) ?: "Drag round to rate", style = Type.footnote.semibold(),
                    color = shown?.let(ScoreColors::color) ?: Color.White.copy(alpha = 0.6f), textAlign = TextAlign.Center,
                    modifier = Modifier.widthIn(min = 120.dp))
                Nudge(Icons.Filled.Add) { onChange(min(100.0, max(1.0, (score ?: 50.0) + 1))) }
            }
        }
    }
}

/// − and + under the dial. Hold to keep nudging.
@Composable
private fun Nudge(icon: ImageVector, step: () -> Unit) {
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }
    val latest by androidx.compose.runtime.rememberUpdatedState(step)
    Box(
        Modifier.size(34.dp).clip(CircleShape).background(Theme.chip).pointerInput(Unit) {
            detectTapGestures(onPress = {
                latest(); Haptics.selection()
                job = scope.launch { delay(450); while (true) { latest(); Haptics.selection(); delay(70) } }
                tryAwaitRelease()
                job?.cancel()
            })
        },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
}

/// A score as a small coloured pill: "87".
@Composable
fun ScorePill(score: Double, fontSize: Float = 11f) {
    val c = ScoreColors.color(score)
    Text(Score.text(score), color = c, style = TextStyle(fontSize = fontSize.sp, fontWeight = FontWeight.ExtraBold),
        modifier = Modifier.background(c.copy(alpha = 0.18f), CircleShape).padding(horizontal = (fontSize * 0.45f).dp, vertical = (fontSize * 0.1f).dp))
}

/// A rating as a score pill or in stars, whichever you picked in Settings.
@Composable
fun SmallRating(rating: Double?) {
    if (rating == null || rating <= 0) return
    if (Prefs.ratingStyle == RatingStyle.STARS) SmallStars(Score.starsShown(rating)) else ScorePill(rating)
}

/// An average (or any worked-out rating) in your scale: "4.2 ★" or a coloured "84".
@Composable
fun RatingValue(score: Double, style: TextStyle = Type.title3) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (Prefs.ratingStyle == RatingStyle.STARS) {
            Text(String.format(Locale.US, "%.1f", Score.toStars(score)), style = style, color = Color.White)
            Icon(Icons.Filled.Star, null, tint = Theme.star, modifier = Modifier.size((style.fontSize.value * 0.6f).dp))
        } else Text(Score.text(score), style = style, color = ScoreColors.color(score))
    }
}

/// A slim 1–100 slider for tight spots: drag along the bar, tap the number to clear it.
@Composable
fun ScoreBar(score: Double?, onChange: ((Double?) -> Unit)? = null) {
    var dragValue by remember { mutableStateOf<Double?>(null) }
    val shown = dragValue ?: score
    val f by animateFloatAsState(((shown ?: 1.0) - 1).toFloat() / 99f, if (dragValue == null) tween(250) else tween(0), label = "bar")
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        BoxWithConstraints(Modifier.weight(1f).height(30.dp).then(if (onChange == null) Modifier else Modifier.pointerInput(Unit) {
            awaitEachGesture {
                val w = size.width.toFloat()
                fun v(x: Float) = (1 + (x / max(w, 1f)).coerceIn(0f, 1f) * 99).roundToInt().toDouble()
                val down = awaitFirstDown()
                var last = v(down.position.x); dragValue = last; Haptics.selection()
                while (true) {
                    val e = awaitPointerEvent()
                    val c = e.changes.firstOrNull() ?: break
                    if (!c.pressed) break
                    val n = v(c.position.x)
                    if (n != last) {
                        if (last.toInt() / 10 != n.toInt() / 10) Haptics.medium() else Haptics.selection()
                        last = n; dragValue = n
                    }
                    c.consume()
                }
                dragValue = null
                onChange(last); Haptics.light()
            }
        }), contentAlignment = Alignment.CenterStart) {
            val w = maxWidth
            Box(Modifier.fillMaxWidth().height(8.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.1f)))
            if (shown != null) {
                // The full gradient, uncovered up to your score, so the end colour matches it.
                Box(Modifier.width(max(8.dp.value, w.value * f).dp).height(8.dp).clip(CircleShape)) {
                    Box(Modifier.width(w).height(8.dp).background(Brush.horizontalGradient(ScoreColors.stops)))
                }
                val knob = if (dragValue != null) 24.dp else 20.dp
                Box(Modifier.offset(x = (w.value * f - knob.value / 2).coerceIn(0f, (w - knob).value).dp).size(knob)
                    .softShadow(3.dp, 1.dp, knob / 2, 0.4f).clip(CircleShape).background(Color.White))
            }
        }
        Text(shown?.let { Score.text(it) } ?: "–", style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End),
            color = shown?.let(ScoreColors::color) ?: Color.White.copy(alpha = 0.4f),
            modifier = Modifier.width(34.dp).clickable(enabled = score != null && onChange != null, indication = null, interactionSource = remember { MutableInteractionSource() }) {
                onChange?.invoke(null); Haptics.light()
            })
    }
}

/// Rating that fits in a row: small stars, or the slim score bar.
@Composable
fun CompactRatingInput(score: Double?, starSize: Dp = 22.dp, onChange: (Double?) -> Unit) {
    if (Prefs.ratingStyle == RatingStyle.STARS) StarRating(score?.let(Score::starsShown), starSize, starSize * 0.2f) { onChange(it?.let(Score::fromStars)) }
    else ScoreBar(score, onChange)
}

/// Rate the way you prefer: the 1–100 dial, or stars (saved as a score, 10 points per half star).
@Composable
fun FilmRatingInput(score: Double?, dialSize: Dp = 200.dp, starSize: Dp = 36.dp, showsHint: Boolean = true, onChange: (Double?) -> Unit) {
    if (Prefs.ratingStyle == RatingStyle.STARS) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            StarRating(score?.let(Score::starsShown), starSize, starSize * 0.22f) { onChange(it?.let(Score::fromStars)) }
            if (showsHint) Text(score?.let { "${Stars.text(Score.starsShown(it))}  ·  ${Score.word(it)}" } ?: "Slide across the stars — half stars work too",
                style = Type.footnote, color = Color.White.copy(alpha = 0.65f))
        }
    } else ScoreDial(score, dialSize, onChange)
}

// MARK: - The drama switch

/// All / Korean / Chinese / Thai / Japanese as a segmented control. Compact shows the flags, small enough
/// to sit beside the greeting on Home.
@Composable
fun DramaFilterBar(selection: DramaFilter, options: List<DramaFilter> = DramaFilter.entries, compact: Boolean = false, onSelect: (DramaFilter) -> Unit) {
    Row(
        Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.1f)).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        for (m in options) {
            val on = m == selection
            val bg by animateColorAsState(if (on) Color.White.copy(alpha = 0.24f) else Color.Transparent, tween(200), label = "seg")
            Box(
                Modifier.clip(CircleShape).background(bg)
                    .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) { if (!on) { Haptics.selection(); onSelect(m) } }
                    .padding(horizontal = if (compact) 9.dp else 11.dp, vertical = if (compact) 6.dp else 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(if (compact) m.flag else m.word, style = (if (compact) Type.subheadline else Type.footnote).semibold(), color = Color.White, maxLines = 1)
            }
        }
    }
}

// MARK: - Layout helpers

@Composable
fun SectionHeader(title: String, subtitle: String? = null, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.Bottom) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Type.title3, color = Color.White)
            if (subtitle != null) Text(subtitle, style = Type.subheadline, color = Theme.dim)
        }
        if (trailing != null) ProvideTextStyle(Type.subheadline.semibold().copy(color = Theme.accent)) { trailing() }
    }
}

/// An accent text button, like a navigation link in a section header.
@Composable
fun TextLink(text: String, color: Color = Theme.accent, onClick: () -> Unit) {
    Text(text, style = LocalTextStyle.current.copy(fontWeight = FontWeight.SemiBold), color = color,
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 2.dp))
}

/// A horizontally scrolling row of posters that opens the show on tap.
@Composable
fun PosterRow(films: List<FilmRef>, width: Dp = 112.dp) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(films, key = { it.id }) { f -> FilmMenuBox(f) { PosterView(f, width = width) } }
    }
}

@Composable
fun PosterGrid(films: List<FilmRef>, columns: Int = 4, modifier: Modifier = Modifier, spacing: Dp = 8.dp, under: (@Composable (FilmRef) -> Unit)? = null) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(if (under != null) 12.dp else spacing)) {
        for (row in films.chunked(columns)) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                for (f in row) {
                    FilmMenuBox(f, Modifier.weight(1f)) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            PosterView(f, corner = 6.dp)
                            under?.invoke(f)
                        }
                    }
                }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = Theme.dim, modifier = Modifier.size(46.dp).padding(bottom = 4.dp))
        Text(title, style = Type.title2, color = Color.White, textAlign = TextAlign.Center)
        Text(message, style = Type.subheadline, color = Theme.dim, textAlign = TextAlign.Center)
    }
}

@Composable
fun ToastView(toast: Toast, onUndo: () -> Unit) {
    Row(
        Modifier.softShadow(16.dp, 4.dp, 30.dp, 0.4f).panel(CircleShape, Color(0xFF242426)).padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(toast.icon, null, tint = Theme.accent, modifier = Modifier.size(18.dp))
        Text(toast.text, style = Type.subheadline.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 260.dp))
        if (toast.undo) Text("Undo", style = Type.subheadline.bold(), color = Theme.accent, modifier = Modifier.clickable(onClick = onUndo))
    }
}

/// A show's title drawn as its official logo, always in colour, or as text when there's no logo.
/// The text never flashes up first: it waits until `ready` says the logo lookup is done and found
/// nothing, the logo fails to load, or five seconds pass with no logo on screen.
@Composable
fun TitleArt(
    title: String,
    logo: String?,
    modifier: Modifier = Modifier,
    aspect: Double = 3.0,
    maxWidth: Dp = 270.dp,
    maxHeight: Dp = 110.dp,
    fontSize: Float = 38f,
    ready: Boolean = true,
) {
    var art by remember { mutableStateOf<LogoBitmaps?>(null) }
    var failed by remember { mutableStateOf(false) }
    var waitedTooLong by remember { mutableStateOf(false) }
    LaunchedEffect(logo) {
        failed = false
        if (logo == null) { art = null; return@LaunchedEffect }
        val b = Images.bitmap(logo)
        if (b == null) { art = null; failed = true; return@LaunchedEffect }
        art = withContext(Dispatchers.Default) { LogoBitmaps.of(b) }
    }
    LaunchedEffect(Unit) { delay(5000); waitedTooLong = true }

    val a = art
    Box(modifier, contentAlignment = Alignment.Center) {
        AnimatedVisibility(a != null, enter = fadeIn(tween(300)), exit = fadeOut(tween(300))) {
            if (a != null) {
                val w = min(maxWidth.value, (maxHeight.value * aspect).toFloat()).dp
                val h = (w.value / max(aspect, 0.1).toFloat()).dp
                // Always the studio's own artwork, in its own colours — never recoloured.
                // A tight edge plus a soft halo keeps any logo readable over bright or dark artwork.
                Canvas(Modifier.width(w).height(h)) {
                    val sx = size.width / a.image.width
                    val sy = size.height / a.image.height
                    drawIntoCanvas { c ->
                        val nc = c.nativeCanvas
                        nc.save()
                        nc.scale(sx, sy)
                        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
                        val shadow = if (a.darkInk) android.graphics.Color.WHITE else android.graphics.Color.BLACK
                        p.color = shadow; p.alpha = ((if (a.darkInk) 0.5f else 0.5f) * 255).toInt()
                        nc.drawBitmap(a.halo, a.haloOffset[0].toFloat(), a.haloOffset[1] + 3f / sy, p)
                        p.alpha = ((if (a.darkInk) 0.35f else 0.55f) * 255).toInt()
                        nc.drawBitmap(a.edge, a.edgeOffset[0].toFloat(), a.edgeOffset[1] + 1f / sy, p)
                        nc.drawBitmap(a.image, 0f, 0f, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
                        nc.restore()
                    }
                }
            }
        }
        if (a == null) {
            if (failed || waitedTooLong || (ready && logo == null)) {
                Text(title.ifEmpty { " " }, color = Color.White, textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis,
                    style = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, fontSize = fontSize.sp, lineHeight = (fontSize * 1.1f).sp,
                        shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(alpha = 0.55f), Offset(0f, 3f), 24f)),
                    modifier = Modifier.widthIn(max = maxWidth))
            } else Spacer(Modifier.width(1.dp).height(maxHeight * 0.7f))
        }
    }
}

/// A logo plus its shadows, worked out once off the main thread.
class LogoBitmaps(val image: Bitmap, val edge: Bitmap, val edgeOffset: IntArray, val halo: Bitmap, val haloOffset: IntArray, val darkInk: Boolean) {
    companion object {
        fun of(b: Bitmap): LogoBitmaps {
            val ink = Palette.logoInk(b)
            /// Dark logos get a light halo instead of a dark shadow, so they read on dark pages.
            val dark = ink == Palette.LogoInk.DARK || ink == Palette.LogoInk.DARK_COLOUR
            val scale = b.width / 270f
            val eo = IntArray(2)
            val ho = IntArray(2)
            val edge = b.extractAlpha(Paint().apply { maskFilter = BlurMaskFilter(max(1f, 2f * scale), BlurMaskFilter.Blur.NORMAL) }, eo)
            val halo = b.extractAlpha(Paint().apply { maskFilter = BlurMaskFilter(max(2f, 16f * scale), BlurMaskFilter.Blur.NORMAL) }, ho)
            return LogoBitmaps(b, edge, eo, halo, ho, dark)
        }
    }
}

// MARK: - Buttons (what used to be glass)

/// A capsule or circle button, filled in the accent when it's the main action.
@Composable
fun Chip(
    modifier: Modifier = Modifier,
    prominent: Boolean = false,
    circle: Boolean = false,
    tint: Color = Theme.accent,
    enabled: Boolean = true,
    onClick: () -> Unit,
    content: @Composable RowScope.() -> Unit,
) {
    val shape = CircleShape
    Row(
        modifier.defaultMinSize(46.dp, 46.dp).clip(shape)
            .background(if (prominent) tint else Theme.chip)
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.45f)
            .padding(horizontal = if (circle) 0.dp else 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        ProvideTextStyle(Type.subheadline.semibold().copy(color = Color.White)) { content() }
    }
}

/// Icon and text side by side, like SwiftUI's Label.
@Composable
fun Label(text: String, icon: ImageVector?, color: Color = LocalTextStyle.current.color.takeOrElse(Color.White), iconSize: Dp = 17.dp, modifier: Modifier = Modifier, maxLines: Int = 1) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (icon != null) Icon(icon, null, tint = color, modifier = Modifier.size(iconSize))
        Text(text, color = color, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
    }
}

private fun Color.takeOrElse(c: Color) = if (this == Color.Unspecified) c else this

enum class ControlSize { SMALL, REGULAR, LARGE }

/// The standard button: a filled capsule (accent when prominent).
@Composable
fun PillButton(
    text: String,
    icon: ImageVector? = null,
    modifier: Modifier = Modifier,
    prominent: Boolean = false,
    size: ControlSize = ControlSize.REGULAR,
    fill: Boolean = false,
    enabled: Boolean = true,
    color: Color = Color.White,
    tint: Color = Theme.accent,
    onClick: () -> Unit,
) {
    val (h, v, style) = when (size) {
        ControlSize.SMALL -> Triple(12.dp, 6.dp, Type.footnote.semibold())
        ControlSize.REGULAR -> Triple(16.dp, 9.dp, Type.subheadline.semibold())
        ControlSize.LARGE -> Triple(20.dp, 14.dp, Type.body.semibold())
    }
    Row(
        modifier.then(if (fill) Modifier.fillMaxWidth() else Modifier).clip(CircleShape)
            .background(if (prominent) tint else Theme.chip)
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.4f)
            .padding(horizontal = h, vertical = v),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        ProvideTextStyle(style.copy(color = color)) { Label(text, icon, color = color, iconSize = (style.fontSize.value + 2).dp) }
    }
}

/// Text-only button in a toolbar.
@Composable
fun BarButton(text: String, color: Color = Theme.accent, bold: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    Text(text, style = Type.body.copy(fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal), color = if (enabled) color else color.copy(alpha = 0.35f),
        modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 8.dp, vertical = 6.dp))
}

/// A round icon button for toolbars.
@Composable
fun IconCircle(icon: ImageVector, description: String, size: Dp = 40.dp, background: Color = Color.Black.copy(alpha = 0.35f), tint: Color = Color.White, onClick: () -> Unit) {
    Box(Modifier.size(size).clip(CircleShape).background(background).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, description, tint = tint, modifier = Modifier.size(size * 0.5f))
    }
}

// MARK: - Avatar & mark

@Composable
fun Avatar(profile: Profile, size: Dp = 40.dp) {
    val bmp = remember(profile.avatarData) {
        profile.avatarData?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() }?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }?.asImageBitmap()
    }
    val initials = profile.name.split(" ").filter { it.isNotBlank() }.take(2).mapNotNull { it.firstOrNull()?.uppercaseChar() }.joinToString("")
    Box(
        Modifier.size(size).clip(CircleShape).background(Brush.linearGradient(listOf(Theme.accent, Theme.heart))).border(0.5.dp, Color.White.copy(alpha = 0.15f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(initials.ifEmpty { "🎬" }, color = Color.White, style = TextStyle(fontSize = (size.value * 0.4f).sp, fontWeight = FontWeight.Bold))
        if (bmp != null) Image(bmp, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    }
}

@Composable
fun MatineeMark(modifier: Modifier = Modifier, size: Dp = 64.dp) {
    Box(
        modifier.size(size).glow(Theme.accent, 20.dp, corner = size * 0.28f, alpha = 0.5f)
            .clip(RoundedCornerShape(size * 0.28f)).background(Brush.linearGradient(listOf(Theme.accent, Theme.heart))),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.ConfirmationNumber, null, tint = Color.Black.copy(alpha = 0.85f), modifier = Modifier.size(size * 0.5f).rotate(-12f))
    }
}

// MARK: - Ambient glow

/// Soft, slow-moving washes of colour pulled from the posters on screen, over OLED black.
@Composable
fun AmbientGlow(urls: List<String>, intensity: Float = 0.38f, modifier: Modifier = Modifier) {
    val colors = remember { mutableStateListOf(Color.Transparent, Color.Transparent, Color.Transparent) }
    LaunchedEffect(urls.take(3)) {
        val out = urls.take(3).mapNotNull { u -> (Palette.cached(u) ?: Palette.of(u))?.glow }
        for (i in 0..2) colors[i] = out.getOrNull(i) ?: Color.Transparent
    }
    val c0 by animateColorAsState(colors[0], tween(1200), label = "g0")
    val c1 by animateColorAsState(colors[1], tween(1200), label = "g1")
    val c2 by animateColorAsState(colors[2], tween(1200), label = "g2")
    val d = LocalDensity.current
    Canvas(modifier.fillMaxSize().background(Color.Black)) {
        val w = size.width
        val h = size.height
        val spots = listOf(Offset(w * 0.15f, h * 0.12f), Offset(w * 0.95f, h * 0.38f), Offset(w * 0.2f, h * 0.78f))
        val radius = w * 0.525f + with(d) { 110.dp.toPx() }
        listOf(c0, c1, c2).forEachIndexed { i, c ->
            if (c.alpha == 0f) return@forEachIndexed
            val a = c.alpha * intensity
            drawCircle(
                Brush.radialGradient(
                    0f to c.copy(alpha = a), 0.35f to c.copy(alpha = a * 0.85f), 0.7f to c.copy(alpha = a * 0.3f), 1f to Color.Transparent,
                    center = spots[i], radius = radius,
                ),
                radius, spots[i],
            )
        }
    }
}

/// OLED black with a glow taken from these posters, behind a screen's content.
@Composable
fun AmbientScreen(films: List<FilmRef>, intensity: Float = 0.38f, content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        AmbientGlow(films.mapNotNull { it.poster }.take(3), intensity)
        content()
    }
}

/// A row of chips that scrolls sideways.
@Composable
fun ChipRow(modifier: Modifier = Modifier, padding: Dp = 20.dp, spacing: Dp = 8.dp, content: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = padding), horizontalArrangement = Arrangement.spacedBy(spacing), verticalAlignment = Alignment.CenterVertically, content = content)
}

/// Like SwiftUI's Divider.
@Composable
fun Hairline(modifier: Modifier = Modifier, color: Color = Theme.line) {
    Box(modifier.fillMaxWidth().height(0.5.dp).background(color))
}

@Composable
fun Liked(on: Boolean, size: Dp = 12.dp) {
    if (on) Icon(Icons.Filled.Favorite, null, tint = Theme.heart, modifier = Modifier.size(size))
}

@Composable
fun WatchlistAdd() = Icon(Icons.Filled.Add, null)

/// The current time, refreshed every `periodMs` — for timers on screen.
@Composable
fun tickingNow(periodMs: Long): androidx.compose.runtime.State<Long> = androidx.compose.runtime.produceState(System.currentTimeMillis(), periodMs) {
    while (true) { delay(periodMs); value = System.currentTimeMillis() }
}
