package com.jm2kool.matinee.model

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/// A lightweight reference to a show — enough to draw a poster and open its page.
/// Show IDs are "tmdbtv-<id>". `lang` is TMDB's original language, which decides the category.
@Serializable
data class FilmRef(
    val id: String,
    val title: String,
    val year: Int? = null,
    val poster: String? = null,
    val backdrop: String? = null,
    val lang: String? = null,
) {
    val yearText: String get() = year?.toString() ?: ""
    val category: Category? get() = Category.of(lang)

    companion object {
        const val SHOW_PREFIX = "tmdbtv-"
    }
}

/// The only four kinds of show Matinee knows about.
enum class Category(val label: String, val short: String, val plural: String, val langs: List<String>, val primaryLang: String, val flag: String, val country: String) {
    KDRAMA("K-drama", "K", "K-dramas", listOf("ko"), "ko", "🇰🇷", "Korean"),
    CDRAMA("C-drama", "C", "C-dramas", listOf("zh", "cn"), "zh", "🇨🇳", "Chinese"),
    THAI("Thai drama", "Thai", "Thai dramas", listOf("th"), "th", "🇹🇭", "Thai"),
    JDRAMA("Japanese drama", "J", "Japanese dramas", listOf("ja"), "ja", "🇯🇵", "Japanese");

    companion object {
        fun of(lang: String?): Category? = entries.firstOrNull { lang != null && lang in it.langs }
        val allLangs: Set<String> = entries.flatMap { it.langs }.toSet()
    }
}

/// The All / K-drama / C-drama / Thai / Japanese switch on Home, the watchlist and the random pick.
enum class DramaFilter(val label: String, val short: String, val category: Category?) {
    ALL("All", "All", null),
    K(Category.KDRAMA.label, "K", Category.KDRAMA),
    C(Category.CDRAMA.label, "C", Category.CDRAMA),
    THAI(Category.THAI.label, "Thai", Category.THAI),
    J(Category.JDRAMA.label, "J", Category.JDRAMA);

    fun includes(f: FilmRef): Boolean = category == null || f.category == category
    val flag: String get() = category?.flag ?: "All"
    /// "Korean", "Chinese"… — short enough for five to sit side by side.
    val word: String get() = category?.country ?: "All"
}

@Serializable
data class Person(val id: String, val name: String, val role: String, val photo: String? = null)

/// Everything shown on a show's page.
data class FilmDetail(
    val ref: FilmRef,
    val tagline: String? = null,
    val overview: String? = null,
    val runtimeMinutes: Int? = null,
    val genres: List<String> = emptyList(),
    val cast: List<Person> = emptyList(),
    val communityRating: Double? = null,
    val voteCount: Int? = null,
    val similar: List<FilmRef> = emptyList(),
    val countries: List<String> = emptyList(),
    val creators: List<String> = emptyList(),
    val networks: List<String> = emptyList(),
    val status: String? = null,
    val seasons: List<SeasonInfo> = emptyList(),
    val lastYear: Int? = null,
    val nextEpisode: Episode? = null,
) {
    /// Seasons that count towards finishing a show: everything except the specials.
    val regularSeasons: List<SeasonInfo> get() = seasons.filter { it.number > 0 && it.episodeCount > 0 }
    val hasEnded: Boolean get() = status == "Ended" || status == "Canceled"
}

data class SeasonInfo(
    val number: Int,
    val name: String,
    val episodeCount: Int,
    val year: Int? = null,
    val poster: String? = null,
    val overview: String? = null,
)

data class Episode(
    val season: Int,
    val number: Int,
    val name: String,
    val overview: String? = null,
    val airDate: LocalDate? = null,
    val runtime: Int? = null,
    val still: String? = null,
    val communityRating: Double? = null,
) {
    val id: String get() = EpisodeKey.make(season, number)
    val code: String get() = EpisodeKey.code(season, number)
    /// Episodes with no date yet haven't aired.
    val aired: Boolean get() = airDate?.let { !it.isAfter(LocalDate.now()) } ?: false
}

object EpisodeKey {
    fun make(season: Int, episode: Int) = "s${season}e$episode"
    fun code(season: Int, episode: Int) = "S$season E$episode"
    fun season(key: String): Int? {
        if (!key.startsWith("s")) return null
        val e = key.indexOf('e')
        if (e < 0) return null
        return key.substring(1, e).toIntOrNull()
    }
    fun episode(key: String): Int? {
        val e = key.indexOf('e')
        if (e < 0) return null
        return key.substring(e + 1).toIntOrNull()
    }
}

/// How far you are through a show: when you ticked off each episode.
@Serializable
data class ShowProgress(
    val show: FilmRef,
    val seen: Map<String, Long> = emptyMap(),      // "s1e3" → when you watched it
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val isEmpty: Boolean get() = seen.isEmpty()
    fun seenCount(season: Int): Int = seen.keys.count { EpisodeKey.season(it) == season }

    /// The furthest episode you've ticked off in the regular seasons.
    val lastSeen: Pair<Int, Int>?
        get() = seen.keys.mapNotNull { k ->
            val s = EpisodeKey.season(k) ?: return@mapNotNull null
            val e = EpisodeKey.episode(k) ?: return@mapNotNull null
            if (s > 0) s to e else null
        }.maxWithOrNull(compareBy({ it.first }, { it.second }))
}

/// One viewing in your diary.
@Serializable
data class LogEntry(
    val id: String = UUID.randomUUID().toString(),
    val film: FilmRef,
    val watchedOn: Long = System.currentTimeMillis(),
    val rating: Double? = null,               // 1–100
    val liked: Boolean = false,
    val rewatch: Boolean = false,
    val review: String = "",
    val tags: List<String> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
)

@Serializable
data class FilmList(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val note: String = "",
    val ranked: Boolean = false,
    val films: List<FilmRef> = emptyList(),
    val updatedAt: Long = System.currentTimeMillis(),
)

@Serializable
data class Profile(
    val name: String = "",
    val bio: String = "",
    val avatarData: String? = null,           // a photo you picked, as base64 JPEG
)

/// The whole library — saved on the phone as one JSON document.
@Serializable
data class LibraryDoc(
    var entries: List<LogEntry> = emptyList(),
    var watchlist: List<FilmRef> = emptyList(),
    var liked: List<FilmRef> = emptyList(),
    var ratings: Map<String, Double> = emptyMap(),     // latest rating per show, 1–100
    var watched: List<FilmRef> = emptyList(),          // shows marked watched (or finished)
    var lists: List<FilmList> = emptyList(),
    var profile: Profile = Profile(),
    var recentSearches: List<String> = emptyList(),
    var taste: TasteProfile? = null,
    var updatedAt: Long = System.currentTimeMillis(),
    var shows: Map<String, ShowProgress> = emptyMap(),
    var favorites: List<FilmRef> = emptyList(),        // up to eight, in your order
    var currentlyWatching: List<FilmRef> = emptyList(),
    var comfort: List<String> = emptyList(),           // ids of comfort shows: watched, never rated
    var watching: List<WatchSession> = emptyList(),
) {
    fun replaceFavorites(list: List<FilmRef>) {
        favorites = list.distinctBy { it.id }.take(MAX_FAVORITES)
    }

    companion object {
        const val MAX_FAVORITES = 8
    }
}

/// How you like to rate. Either way the library stores a score out of 100, so switching
/// back and forth never loses anything: stars show it in half steps (10 points each).
enum class RatingStyle { SCORE, STARS }

/// Shows are scored 1–100.
object Score {
    fun fromStars(s: Double): Double = min(100.0, max(1.0, (s * 20).roundToInt().toDouble()))
    fun toStars(s: Double): Double = s / 20
    /// A score as the nearest half star, for showing it in stars.
    fun starsShown(s: Double): Double = max(0.5, (s / 10).roundToInt() / 2.0)
    fun word(s: Double): String = when {
        s < 20 -> "Awful"
        s < 40 -> "Not for me"
        s < 55 -> "Meh"
        s < 70 -> "Good"
        s < 85 -> "Great"
        s < 95 -> "Brilliant"
        else -> "Masterpiece"
    }
    fun text(s: Double?): String = s?.let { if (it > 0) it.roundToInt().toString() else "" } ?: ""
    /// An average in the scale you rate with: "4.2 ★" or "84".
    fun describe(s: Double, style: RatingStyle): String =
        if (style == RatingStyle.STARS) String.format(Locale.US, "%.1f ★", toStars(s)) else text(s)
}

object Stars {
    fun text(r: Double?): String {
        if (r == null || r <= 0) return ""
        val full = r.toInt()
        return "★".repeat(full) + if (r - full >= 0.5) "½" else ""
    }
}

// MARK: Dates

object Dates {
    private val zone get() = ZoneId.systemDefault()
    fun localDate(millis: Long): LocalDate = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
    fun startOfDay(d: LocalDate): Long = d.atStartOfDay(zone).toInstant().toEpochMilli()
    fun year(millis: Long): Int = localDate(millis).year
    fun monthYear(millis: Long): String = localDate(millis).format(DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault()))
    fun dayNumber(millis: Long): String = localDate(millis).dayOfMonth.toString()
    fun weekdayShort(millis: Long): String = localDate(millis).dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault())
    fun abbreviated(millis: Long): String = localDate(millis).format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault()))
    fun dayMonth(d: LocalDate): String = d.format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault()))
    fun weekdayDayMonth(d: LocalDate): String = d.format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.getDefault()))
    fun long(d: LocalDate): String = d.format(DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.getDefault()))
    fun isToday(millis: Long) = localDate(millis) == LocalDate.now()
    fun isYesterday(millis: Long) = localDate(millis) == LocalDate.now().minusDays(1)

    /// "2 days ago", "yesterday", "just now".
    fun relative(millis: Long): String {
        val diff = (System.currentTimeMillis() - millis) / 1000
        return when {
            diff < 60 -> "just now"
            diff < 3600 -> "${diff / 60} min ago"
            diff < 86_400 -> "${diff / 3600} hr ago"
            localDate(millis) == LocalDate.now().minusDays(1) -> "yesterday"
            diff < 7 * 86_400 -> "${diff / 86_400} days ago"
            diff < 30 * 86_400 -> "${diff / (7 * 86_400)} wk ago"
            else -> abbreviated(millis)
        }
    }
}

/// "1h 12m", "34m", "0m".
fun filmClock(seconds: Double): String {
    val m = (seconds / 60).toInt()
    val h = m / 60
    return if (h > 0) "${h}h ${m % 60}m" else "${m}m"
}
