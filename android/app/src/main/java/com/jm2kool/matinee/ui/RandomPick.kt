package com.jm2kool.matinee.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.runtime.mutableFloatStateOf
import com.jm2kool.matinee.model.DramaFilter
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/// Your watchlist, shuffled into a swipe deck. Swipe left to see the next pick, right (or tap) and the card
/// grows into its page; ↺ brings back the last one. Choose a category at the top; tap outside to close.
@Composable
fun RandomPickDeck(films: List<FilmRef>, onClose: () -> Unit) {
    var index by remember { mutableIntStateOf(0) }
    val drag = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    val appear = remember { Animatable(0f) }
    val expand = remember { Animatable(0f) }
    var expanded by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val d = LocalDensity.current
    val far = with(d) { 700.dp.toPx() }
    LaunchedEffect(Unit) { appear.animateTo(1f, spring(0.6f, Spring.StiffnessMediumLow)) }
    LaunchedEffect(Router.randomDeckID) { drag.snapTo(Offset.Zero); index = 0 }

    /// The top card flies off to the left and the next one comes up.
    fun skip() {
        if (index >= films.size) return
        Haptics.light()
        scope.launch {
            drag.animateTo(Offset(-far, drag.value.y + 40f), tween(220, easing = FastOutLinearInEasing))
            index += 1
            drag.snapTo(Offset.Zero)
        }
    }
    /// The last card you skipped slides back in from the left.
    fun rewind() {
        if (index <= 0) return
        Haptics.light()
        scope.launch {
            drag.snapTo(Offset(-far, 0f)); index -= 1
            drag.animateTo(Offset.Zero, spring(0.8f, Spring.StiffnessMediumLow))
        }
    }
    /// Grow the card to fill the screen, slip the show's page in underneath, then fade the card away.
    fun open(f: FilmRef) {
        if (expanded) return
        expanded = true
        Router.randomPickOpening = true
        Haptics.light()
        scope.launch {
            drag.animateTo(Offset.Zero, tween(200))
            expand.animateTo(1f, tween(450, easing = FastOutSlowInEasing))
            Router.open(f)
            delay(300)
            onClose()
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.85f + 0.15f * expand.value))
        .pointerInput(Unit) { detectTapGestures { if (!expanded) onClose() } }) {
        val fullW = maxWidth
        val fullH = maxHeight
        val cardH = max(240f, min(min(300f, fullW.value - 64) * 1.5f, fullH.value - 380)).dp
        val cardW = cardH / 1.5f
        val chrome = 1f - expand.value
        Column(Modifier.fillMaxSize().graphicsLayer {
            val s = 0.6f + 0.4f * appear.value; scaleX = s; scaleY = s; alpha = appear.value.coerceIn(0f, 1f)
        }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
            Column(Modifier.graphicsLayer { alpha = chrome }.zIndex(0f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("FROM YOUR WATCHLIST", style = Type.caption.heavy().tracking(1.4f), color = Theme.accent)
                DramaFilterBar(Router.randomKind, DramaFilter.entries) { Router.randomKind = it; Router.deal() }
            }
            var slotCentre by remember { mutableFloatStateOf(Float.NaN) }
            val screenCentre = with(d) { fullH.toPx() } / 2
            Box(Modifier.width(cardW).height(cardH).zIndex(1f).onGloballyPositioned { slotCentre = it.positionInRoot().y + it.size.height / 2f },
                contentAlignment = Alignment.Center) {
                if (index >= films.size) EndCard(films, Modifier.width(cardW).height(cardH))
                for ((i, f) in films.withIndex().filter { it.index >= index && it.index < index + 3 }.reversed()) key(f.id) {
                    val depth = i - index
                    val top = depth == 0
                    val w = if (top) lerp(cardW, fullW, expand.value) else cardW
                    val h = if (top) lerp(cardH, fullH, expand.value) else cardH
                    DeckCard(
                        f, "THIS ONE", "NEXT", Theme.accent, lean = if (top) with(d) { drag.value.x.toDp() }.value else 0f, expanded = top && expanded,
                        modifier = Modifier.requiredSize(w, h).zIndex(-depth.toFloat()).graphicsLayer {
                            val s = 1f - depth * 0.05f
                            scaleX = s; scaleY = s
                            val centring = if (top && !slotCentre.isNaN()) (screenCentre - slotCentre) * expand.value else 0f
                            translationY = depth * 14.dp.toPx() + (if (top) drag.value.y else 0f) + centring
                            translationX = if (top) drag.value.x else 0f
                            rotationZ = if (top) drag.value.x / density / 22f else 0f
                            transformOrigin = TransformOrigin(0.5f, 1f)
                            alpha = if (expanded && !top) 0f else 1f
                        }.then(if (!top || expanded) Modifier else Modifier
                            .pointerInput(f.id) { detectTapGestures { open(f) } }
                            .pointerInput(f.id) {
                                val tracker = VelocityTracker()
                                detectDragGestures(
                                    onDragStart = { tracker.resetTracking() },
                                    onDragEnd = {
                                        val v = tracker.calculateVelocity()
                                        val x = drag.value.x
                                        val predicted = x + v.x * 0.25f
                                        if (abs(x) > 110.dp.toPx() || abs(predicted) > 380.dp.toPx()) {
                                            if ((if (abs(predicted) > abs(x)) predicted else x) < 0) skip() else open(f)
                                        } else scope.launch { drag.animateTo(Offset.Zero, spring(0.7f, Spring.StiffnessMediumLow)) }
                                    },
                                ) { change, amount ->
                                    change.consume()
                                    tracker.addPosition(change.uptimeMillis, change.position)
                                    scope.launch { drag.snapTo(drag.value + amount) }
                                }
                            }),
                    )
                }
            }
            Column(Modifier.graphicsLayer { alpha = chrome }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (index < films.size) Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
                    RoundButton(Icons.AutoMirrored.Filled.Undo, 48.dp, Color.White.copy(alpha = if (index > 0) 0.85f else 0.3f), "Previous pick", enabled = index > 0) { rewind() }
                    RoundButton(Icons.Filled.Close, 60.dp, Color.White, "Another pick") { skip() }
                    RoundButton(Icons.Filled.PlayArrow, 60.dp, Theme.accent, "Open this one") { films.getOrNull(index)?.let { open(it) } }
                }
                Text(when {
                    films.isEmpty() -> "Nothing to pick from yet"
                    index < films.size -> "Swipe left for another · right or tap to open"
                    else -> "Shake to shuffle again"
                }, style = Type.footnote.semibold(), color = Color.White.copy(alpha = 0.7f), textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
private fun EndCard(films: List<FilmRef>, modifier: Modifier) {
    Column(modifier.panel(RoundedCornerShape(32.dp)).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
        Text(if (films.isEmpty()) "📺" else "🍿", fontSize = 54.sp)
        if (films.isEmpty()) {
            Text("No ${Router.randomKind.category?.plural ?: "shows"} on your watchlist", style = Type.headline, color = Color.White, textAlign = TextAlign.Center)
            Text("Save a few and they'll turn up here, or try another category.", style = Type.subheadline, color = Theme.dim, textAlign = TextAlign.Center)
        } else {
            Text("That's all ${films.size}", style = Type.title3, color = Color.White)
            Text("You've been through every pick.", style = Type.subheadline, color = Theme.dim, textAlign = TextAlign.Center)
            PillButton("Shuffle again", Icons.Filled.Shuffle, prominent = true) { Router.deal() }
        }
    }
}

