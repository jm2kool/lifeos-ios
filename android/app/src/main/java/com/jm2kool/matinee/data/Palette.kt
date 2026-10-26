package com.jm2kool.matinee.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color as AColor
import androidx.compose.ui.graphics.Color
import androidx.core.graphics.drawable.toBitmap
import coil.ImageLoader
import coil.disk.DiskCache
import coil.memory.MemoryCache
import coil.request.ImageRequest
import coil.request.SuccessResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min

/// One image loader for the whole app: posters on screen, and bitmaps for colours and logos.
object Images {
    lateinit var loader: ImageLoader
        private set
    private lateinit var context: Context

    fun init(c: Context) {
        context = c.applicationContext
        loader = ImageLoader.Builder(context)
            .okHttpClient { Catalog.client }
            .memoryCache { MemoryCache.Builder(context).maxSizePercent(0.25).build() }
            .diskCache { DiskCache.Builder().directory(context.cacheDir.resolve("images")).maxSizeBytes(300L shl 20).build() }
            .respectCacheHeaders(false)
            .build()
    }

    /// A software bitmap, for reading pixels.
    suspend fun bitmap(url: String, size: Int? = null): Bitmap? {
        val req = ImageRequest.Builder(context).data(url).allowHardware(false).apply { size?.let { size(it) } }.build()
        val r = loader.execute(req) as? SuccessResult ?: return null
        return runCatching { r.drawable.toBitmap() }.getOrNull()
    }
}

/// The colours pulled out of a poster: the dominant vibrant "accent" plus a small palette.
data class PosterPalette(val accentArgb: Int, val colors: List<Int>) {
    val accent: Color get() = Color(accentArgb)
    /// A version of the accent dark enough that white text on top always reads well.
    val background: Color get() = Color(adjusted(accentArgb, maxBrightness = 0.36f, minSaturation = 0.35f))
    /// A slightly lighter tone for cards sitting on the background.
    val surface: Color get() = Color(adjusted(accentArgb, maxBrightness = 0.5f, minSaturation = 0.3f)).copy(alpha = 0.55f)
    /// A vivid version of the accent for glows behind posters and pages.
    val glow: Color get() = Color(adjusted(accentArgb, maxBrightness = 0.95f, minSaturation = 0.5f, minBrightness = 0.55f))
    /// A bright tint for highlights (stars, links) on the background.
    val highlight: Color get() = Color(adjusted(accentArgb, maxBrightness = 1f, minSaturation = 0.45f, minBrightness = 0.85f))
}

fun adjusted(argb: Int, maxBrightness: Float, minSaturation: Float, minBrightness: Float = 0.12f): Int {
    val hsv = FloatArray(3)
    AColor.colorToHSV(argb, hsv)
    val s = hsv[1]
    hsv[1] = if (s < 0.08f) s else max(s, minSaturation)
    hsv[2] = min(max(hsv[2], minBrightness), maxBrightness)
    return AColor.HSVToColor(hsv)
}

object Palette {
    private val cache = ConcurrentHashMap<String, PosterPalette>()

    fun cached(url: String?): PosterPalette? = url?.let { cache[it] }

    suspend fun of(url: String?): PosterPalette? {
        if (url == null) return null
        cache[url]?.let { return it }
        val bmp = Images.bitmap(url, 200) ?: return null
        val swatches = withContext(Dispatchers.Default) { extract(bmp) }
        val first = swatches.firstOrNull() ?: return null
        val accent = swatches.firstOrNull { it.saturation > 0.28 && it.brightness > 0.2 } ?: first
        val p = PosterPalette(accent.argb, listOf(accent.argb) + swatches.filter { it !== accent }.map { it.argb })
        cache[url] = p
        return p
    }

    class Swatch(val r: Double, val g: Double, val b: Double, val weight: Double) {
        val argb: Int get() = AColor.rgb((r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt())
        val saturation: Double get() { val mx = maxOf(r, g, b); val mn = minOf(r, g, b); return if (mx == 0.0) 0.0 else (mx - mn) / mx }
        val brightness: Double get() = maxOf(r, g, b)
    }

    /// Downsample, bucket pixels by hue, and rank buckets by how much — and how vividly — they appear.
    fun extract(image: Bitmap): List<Swatch> {
        val w = 36
        val h = 54
        val small = Bitmap.createScaledBitmap(image, w, h, true)
        val px = IntArray(w * h)
        small.getPixels(px, 0, w, 0, 0, w, h)
        val bins = 13   // 12 hues + 1 neutral
        val ar = DoubleArray(bins); val ag = DoubleArray(bins); val ab = DoubleArray(bins)
        val an = DoubleArray(bins); val score = DoubleArray(bins)
        for (c in px) {
            val r = AColor.red(c) / 255.0
            val g = AColor.green(c) / 255.0
            val b = AColor.blue(c) / 255.0
            val mx = maxOf(r, g, b)
            val mn = minOf(r, g, b)
            if (mx < 0.1) continue                          // skip near-black
            val s = if (mx == 0.0) 0.0 else (mx - mn) / mx
            if (s < 0.08 && mx > 0.92) continue             // skip near-white
            var hue = 0.0
            if (mx != mn) {
                val d = mx - mn
                hue = when (mx) {
                    r -> ((g - b) / d) % 6
                    g -> (b - r) / d + 2
                    else -> (r - g) / d + 4
                }
                hue = (hue * 60 + 360) % 360
            }
            val bin = if (s < 0.18) 12 else (hue / 30).toInt() % 12
            ar[bin] += r; ag[bin] += g; ab[bin] += b; an[bin] += 1.0
            score[bin] += 0.35 + s * 1.6 + mx * 0.4
        }
        return (0 until bins).filter { an[it] > 4 }.sortedByDescending { score[it] }.take(5)
            .map { Swatch(ar[it] / an[it], ag[it] / an[it], ab[it] / an[it], score[it]) }
    }

    enum class LogoInk { COLOUR, DARK_COLOUR, LIGHT, DARK }

    /// What a logo is drawn in: real colours, or plain white / black ink.
    fun logoInk(image: Bitmap): LogoInk {
        val w = 48
        val h = 48
        val small = Bitmap.createScaledBitmap(image, w, h, true)
        val px = IntArray(w * h)
        small.getPixels(px, 0, w, 0, 0, w, h)
        var lum = 0.0
        var weight = 0.0
        var colourful = 0.0
        for (c in px) {
            val a = AColor.alpha(c) / 255.0
            if (a <= 0.3) continue
            // Android bitmaps aren't premultiplied in getPixels, so the channels are already the ink's colour.
            val r = AColor.red(c) / 255.0
            val g = AColor.green(c) / 255.0
            val b = AColor.blue(c) / 255.0
            val mx = maxOf(r, g, b)
            val mn = minOf(r, g, b)
            if (mx > 0.12 && (mx - mn) / max(mx, 0.001) > 0.25) colourful += a
            lum += (0.299 * r + 0.587 * g + 0.114 * b) * a
            weight += a
        }
        if (weight <= 0) return LogoInk.COLOUR
        val l = lum / weight
        // Even a little real colour (a red stripe, a gold outline) means the designer chose colours: keep them.
        if (colourful / weight > 0.12) return if (l < 0.3) LogoInk.DARK_COLOUR else LogoInk.COLOUR
        return if (l < 0.45) LogoInk.DARK else LogoInk.LIGHT
    }
}

/// A big version of the poster for full-screen use.
val com.jm2kool.matinee.model.FilmRef.largePoster: String?
    get() = poster?.let { if ("image.tmdb.org" in it) it.replace("/w500/", "/original/") else it }
