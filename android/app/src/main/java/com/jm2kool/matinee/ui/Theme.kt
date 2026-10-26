package com.jm2kool.matinee.ui

import android.graphics.BlurMaskFilter
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object Theme {
    val bg = Color.Black                                    // true OLED black
    val card = Color(0.07f, 0.07f, 0.07f)
    val line = Color.White.copy(alpha = 0.08f)
    val accent = Color(1.0f, 0.42f, 0.24f)                  // marquee orange
    val star = Color(1.0f, 0.74f, 0.18f)                    // amber
    val heart = Color(1.0f, 0.36f, 0.47f)
    val watch = Color(0.32f, 0.83f, 0.55f)
    val list = Color(0.42f, 0.62f, 1.0f)
    val dim = Color.White.copy(alpha = 0.55f)
    /// What used to be Liquid Glass: a plain, slightly lifted surface.
    val panel = Color.White.copy(alpha = 0.08f)
    val chip = Color.White.copy(alpha = 0.12f)
}

/// iOS text styles, in the same sizes.
object Type {
    val largeTitle = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, lineHeight = 41.sp)
    val title = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold, lineHeight = 34.sp)
    val title2 = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, lineHeight = 28.sp)
    val title3 = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, lineHeight = 25.sp)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp)
    val body = TextStyle(fontSize = 17.sp, lineHeight = 22.sp)
    val callout = TextStyle(fontSize = 16.sp, lineHeight = 21.sp)
    val subheadline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontSize = 12.sp, lineHeight = 16.sp)
    val caption2 = TextStyle(fontSize = 11.sp, lineHeight = 13.sp)

    fun TextStyle.semibold() = copy(fontWeight = FontWeight.SemiBold)
    fun TextStyle.bold() = copy(fontWeight = FontWeight.Bold)
    fun TextStyle.heavy() = copy(fontWeight = FontWeight.ExtraBold)
    fun TextStyle.tracking(em: Float) = copy(letterSpacing = em.sp)
    val serif = FontFamily.Serif
}

@Composable
fun MatineeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Theme.accent,
            onPrimary = Color.White,
            background = Theme.bg,
            surface = Theme.bg,
            onSurface = Color.White,
            onBackground = Color.White,
            surfaceVariant = Theme.card,
            secondaryContainer = Theme.accent.copy(alpha = 0.3f),
        ),
        content = content,
    )
}

/// The replacement for a glass panel: a soft dark surface with a hairline edge.
fun Modifier.panel(shape: Shape = RoundedCornerShape(28.dp), color: Color = Theme.panel): Modifier =
    this.background(color, shape).border(0.5.dp, Theme.line, shape)

/// A soft halo in a colour, like SwiftUI's coloured shadow.
fun Modifier.glow(color: Color, radius: Dp, offsetY: Dp = 0.dp, corner: Dp = 8.dp, alpha: Float = 0.55f): Modifier = composed {
    if (color.alpha == 0f || alpha == 0f) return@composed this
    val d = LocalDensity.current
    val r = with(d) { radius.toPx() }
    val oy = with(d) { offsetY.toPx() }
    val c = with(d) { corner.toPx() }
    this.drawBehind {
        drawIntoCanvas { canvas ->
            val paint = Paint()
            val fp = paint.asFrameworkPaint()
            fp.isAntiAlias = true
            fp.color = color.copy(alpha = alpha).toArgb()
            if (r > 0) fp.maskFilter = BlurMaskFilter(r, BlurMaskFilter.Blur.NORMAL)
            canvas.nativeCanvas.drawRoundRect(0f, oy, size.width, size.height + oy, c, c, fp)
        }
    }
}

/// A dark drop shadow (SwiftUI's .shadow(color: .black…)).
fun Modifier.softShadow(radius: Dp, offsetY: Dp = 0.dp, corner: Dp = 0.dp, alpha: Float = 0.5f) = glow(Color.Black, radius, offsetY, corner, alpha)

