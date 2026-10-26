package com.jm2kool.matinee.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.tracking
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/// Opening titles: an old film-leader countdown (3, 2, 1) with projector flicker and grain,
/// a flash of projector light, then the ticket mark punches in and the wordmark rises
/// before everything zooms through into the app. Tap to skip.
@Composable
fun SplashView(onFinish: () -> Unit) {
    val countdownEnd = 1.15f
    val flashEnd = 1.4f
    val brandEnd = 2.25f
    val total = 2.75f
    var t by remember { mutableFloatStateOf(0f) }
    var finished by remember { mutableStateOf(false) }
    fun finish() { if (!finished) { finished = true; onFinish() } }
    LaunchedEffect(Unit) {
        Haptics.light()
        val start = withFrameMillis { it }
        while (!finished) {
            val now = withFrameMillis { it }
            t = (now - start) / 1000f
            if (t >= total) finish()
        }
    }
    fun flash(t: Float): Float {
        if (t <= countdownEnd - 0.08f || t >= flashEnd) return 0f
        val p = (t - (countdownEnd - 0.08f)) / (flashEnd - countdownEnd + 0.08f)
        return if (p < 0.25f) p / 0.25f * 0.95f else 0.95f * (1 - (p - 0.25f) / 0.75f)
    }

    Box(
        Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures { finish() } }
            .graphicsLayer {
                val s = if (t > brandEnd) 1 + (t - brandEnd) * 1.1f else 1f
                scaleX = s; scaleY = s
                alpha = if (t > brandEnd) max(0f, 1 - (t - brandEnd) / (total - brandEnd)) else 1f
            },
        contentAlignment = Alignment.Center,
    ) {
        if (t < countdownEnd) Leader(t, countdownEnd)
        if (t >= countdownEnd - 0.05f) Brand(max(0f, t - flashEnd + 0.15f))
        // Projector flash between the leader and the titles.
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = flash(t) }.background(Color.White))
        Grain((t * 24).toInt(), if (t < flashEnd) 0.16f else 0.07f)
    }
}

@Composable
private fun Leader(t: Float, countdownEnd: Float) {
    val step = countdownEnd / 3
    val n = 3 - min(2, (t / step).toInt())
    val local = (t % step) / step
    // Old projectors flicker: a small, irregular brightness wobble.
    val flicker = 0.82f + 0.18f * abs(sin(t * 47) * cos(t * 13))
    Canvas(Modifier.fillMaxSize()) {
        val side = min(size.width, size.height) * 0.78f
        val c = Offset(size.width / 2, size.height / 2)
        drawRect(Brush.radialGradient(listOf(Color(0.42f * flicker, 0.42f * flicker, 0.42f * flicker), Color(0.16f * flicker, 0.16f * flicker, 0.16f * flicker)),
            center = c, radius = size.height * 0.7f))
        // Crosshair
        drawRect(Color.Black.copy(alpha = 0.55f), Offset(c.x - 1, 0f), Size(2f, size.height))
        drawRect(Color.Black.copy(alpha = 0.55f), Offset(0f, c.y - 1), Size(size.width, 2f))
        drawCircle(Color.White.copy(alpha = 0.75f * flicker), side / 2, c, style = Stroke(3.dp.toPx()))
        drawCircle(Color.White.copy(alpha = 0.5f * flicker), side * 0.41f, c, style = Stroke(2.dp.toPx()))
        // Sweeping arm, filling the dial like a clock wipe.
        val r = side * 0.41f
        drawArc(Color.Black.copy(alpha = 0.28f), -90f, 360 * local, true, Offset(c.x - r, c.y - r), Size(r * 2, r * 2))
        // The number, in a heavy serif.
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.White.copy(alpha = 0.92f * flicker).toArgb()
            textSize = side * 0.5f * (1 + (1 - local) * 0.06f)
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.SERIF, android.graphics.Typeface.BOLD)
            textAlign = android.graphics.Paint.Align.CENTER
            setShadowLayer(4f, 0f, 0f, android.graphics.Color.argb(128, 0, 0, 0))
        }
        val fm = paint.fontMetrics
        drawContext.canvas.nativeCanvas.drawText("$n", c.x, c.y - (fm.ascent + fm.descent) / 2, paint)
        // Scratches and dust
        val rng = SeededRandom((t * 18).toLong() * 2_654_435_761L)
        repeat(3) {
            val x = rng.next() * size.width
            val top = rng.next() * size.height * 0.5f
            drawLine(Color.White.copy(alpha = 0.18f), Offset(x, top), Offset(x + (rng.next() - 0.5f) * 6, top + size.height * (0.2f + rng.next() * 0.6f)), 1f)
        }
        // Vignette
        drawRect(Brush.radialGradient(0f to Color.Transparent, (side * 0.45f) / (size.height * 0.75f) to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f),
            center = c, radius = size.height * 0.75f))
    }
}

@Composable
private fun Brand(local: Float) {
    val markIn = min(1f, local / 0.45f)
    val spring = if (markIn >= 1) 1f else 1 - (1 - markIn).pow(3) * cos(markIn * PI.toFloat() * 2.2f)
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        // Warm projector glow behind the mark.
        Canvas(Modifier.fillMaxSize()) {
            val c = Offset(size.width / 2, size.height / 2)
            val d = density
            drawCircle(Brush.radialGradient(listOf(Theme.accent.copy(alpha = 0.55f * markIn), Color.Transparent), center = c + Offset(-60 * d, -80 * d), radius = 280 * d),
                280 * d, c + Offset(-60 * d, -80 * d))
            drawCircle(Brush.radialGradient(listOf(Theme.heart.copy(alpha = 0.45f * markIn), Color.Transparent), center = c + Offset(80 * d, 90 * d), radius = 260 * d),
                260 * d, c + Offset(80 * d, 90 * d))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Box(Modifier.graphicsLayer {
                val s = 0.3f + 0.7f * spring; scaleX = s; scaleY = s; rotationZ = (1 - spring) * -40f; alpha = markIn
            }) { MatineeMark(size = 92.dp) }
            Row {
                "Matinee".forEachIndexed { i, ch ->
                    val p = ((local - 0.18f - i * 0.045f) / 0.3f).coerceIn(0f, 1f)
                    Text(ch.toString(), color = Color.White, style = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.ExtraBold, fontSize = 52.sp),
                        modifier = Modifier.graphicsLayer { translationY = (1 - p) * 26 * density; alpha = p })
                }
            }
            Text("NOW SHOWING · YOUR DRAMAS", style = Type.caption.heavy().tracking(3f), color = Color.White.copy(alpha = 0.6f),
                modifier = Modifier.graphicsLayer { alpha = ((local - 0.5f) / 0.3f).coerceIn(0f, 1f) })
        }
    }
}

/// Film grain: speckles that change every frame.
@Composable
private fun Grain(seed: Int, alpha: Float) {
    Canvas(Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha }) {
        val rng = SeededRandom(seed.toLong() * 40_503L + 7)
        repeat(900) {
            val x = rng.next() * size.width
            val y = rng.next() * size.height
            val s = (0.6f + rng.next() * 1.4f) * density / 2
            drawCircle(if (rng.next() > 0.5f) Color.White else Color.Black, s, Offset(x, y))
        }
    }
}

class SeededRandom(seed: Long) {
    private var state: Long = if (seed == 0L) -0x61c8864680b583ebL else seed
    /// 0..<1
    fun next(): Float {
        state = state xor (state shl 13); state = state xor (state ushr 7); state = state xor (state shl 17)
        return ((state % 10_000 + 10_000) % 10_000) / 10_000f
    }
}

@Suppress("unused")
private val unusedBlend = BlendMode.Plus
