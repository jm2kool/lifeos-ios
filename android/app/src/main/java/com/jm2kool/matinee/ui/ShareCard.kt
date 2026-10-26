package com.jm2kool.matinee.ui

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.FileProvider
import com.jm2kool.matinee.data.Images
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.RatingStyle
import com.jm2kool.matinee.model.Score
import com.jm2kool.matinee.model.Stars
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.max
import kotlin.math.min

/// A story-sized picture of a show — poster, logo and your rating — to share anywhere.
object ShareCard {
    private const val W = 1080
    private const val H = 1920

    suspend fun share(ctx: Context, film: FilmRef, poster: String?, logo: String?, rating: Double?, liked: Boolean, tint: Color) {
        val p = poster?.let { Images.bitmap(it) }
        val l = logo?.let { Images.bitmap(it) }
        val file = withContext(Dispatchers.Default) {
            val bmp = render(film, p, l, rating, liked, tint)
            val dir = File(ctx.cacheDir, "shared").apply { mkdirs() }
            File(dir, "matinee-story.png").also { f -> f.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) } }
        }
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(Intent.createChooser(send, film.title))
    }

    fun render(film: FilmRef, poster: Bitmap?, logo: Bitmap?, rating: Double?, liked: Boolean, tint: Color): Bitmap {
        val bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(android.graphics.Color.BLACK)
        c.drawColor(tint.copy(alpha = 0.35f).toArgb())
        if (poster != null) {
            // Fill the card, cropping the poster's edges.
            val s = max(W / poster.width.toFloat(), H / poster.height.toFloat())
            val w = poster.width * s
            val h = poster.height * s
            c.drawBitmap(poster, null, RectF((W - w) / 2, (H - h) / 2, (W + w) / 2, (H + h) / 2), Paint(Paint.FILTER_BITMAP_FLAG))
        }
        c.drawRect(0f, 0f, W.toFloat(), H.toFloat(), Paint().apply {
            shader = LinearGradient(0f, 0f, 0f, H.toFloat(), intArrayOf(0, 0, android.graphics.Color.argb(217, 0, 0, 0), android.graphics.Color.BLACK),
                floatArrayOf(0f, 0.4f, 0.78f, 1f), Shader.TileMode.CLAMP)
        })

        // Bottom-up: the Matinee mark, the year, the rating, then the logo or title.
        var y = H - 150f
        val white = android.graphics.Color.WHITE
        val serif = Typeface.create(Typeface.SERIF, Typeface.BOLD)
        val brand = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = white; textSize = 50f; typeface = serif; textAlign = Paint.Align.LEFT }
        val markSize = 64f
        val brandW = markSize + 14 + brand.measureText("Matinee")
        val bx = (W - brandW) / 2
        val markRect = RectF(bx, y - markSize, bx + markSize, y)
        c.drawRoundRect(markRect, 18f, 18f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(markRect.left, markRect.top, markRect.right, markRect.bottom, Theme.accent.toArgb(), Theme.heart.toArgb(), Shader.TileMode.CLAMP)
        })
        c.drawText("🎟", markRect.centerX() - 18, markRect.centerY() + 14, Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 36f })
        c.drawText("Matinee", bx + markSize + 14, y - 12, brand)
        y -= markSize + 30 + 34

        val year = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.argb(191, 255, 255, 255); textSize = 44f; textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD }
        val sub = listOfNotNull(film.yearText.ifEmpty { null }, film.category?.label).joinToString(" · ")
        c.drawText(sub, W / 2f, y, year)
        y -= 44 + 34

        if ((rating != null && rating > 0) || liked) {
            val parts = ArrayList<Pair<String, Paint>>()
            if (rating != null && rating > 0) {
                if (Prefs.ratingStyle == RatingStyle.STARS) parts += Stars.text(Score.starsShown(rating)) to Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Theme.star.toArgb(); textSize = 84f }
                else {
                    parts += Score.text(rating) to Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ScoreColors.color(rating).toArgb(); textSize = 130f; typeface = Typeface.DEFAULT_BOLD }
                    parts += "/100" to Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ScoreColors.color(rating).copy(alpha = 0.6f).toArgb(); textSize = 44f; typeface = Typeface.DEFAULT_BOLD }
                }
            }
            if (liked) parts += " ♥" to Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Theme.heart.toArgb(); textSize = 80f }
            val total = parts.sumOf { it.second.measureText(it.first).toDouble() }.toFloat() + 10 * (parts.size - 1)
            var x = (W - total) / 2
            for ((t, p) in parts) { c.drawText(t, x, y, p); x += p.measureText(t) + 10 }
            y -= 130 + 34
        }

        if (logo != null) {
            val s = min(760f / logo.width, 300f / logo.height)
            val w = logo.width * s
            val h = logo.height * s
            val r = RectF((W - w) / 2, y - h, (W + w) / 2, y)
            val shadow = logo.extractAlpha(Paint().apply { maskFilter = android.graphics.BlurMaskFilter(30f, android.graphics.BlurMaskFilter.Blur.NORMAL) }, IntArray(2))
            c.drawBitmap(shadow, null, RectF(r.left - 30 * s, r.top - 30 * s, r.right + 30 * s, r.bottom + 30 * s), Paint().apply { color = android.graphics.Color.argb(150, 0, 0, 0) })
            c.drawBitmap(logo, null, r, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        } else {
            val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = white; textSize = 110f; typeface = serif }
            val layout = StaticLayout.Builder.obtain(film.title, 0, film.title.length, tp, W - 180).setAlignment(Layout.Alignment.ALIGN_CENTER).setMaxLines(3).build()
            c.save(); c.translate(90f, y - layout.height); layout.draw(c); c.restore()
        }
        return bmp
    }
}
