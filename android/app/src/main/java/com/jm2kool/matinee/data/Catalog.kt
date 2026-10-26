package com.jm2kool.matinee.data

import android.content.Context
import com.jm2kool.matinee.BuildConfig
import com.jm2kool.matinee.model.Category
import com.jm2kool.matinee.model.Episode
import com.jm2kool.matinee.model.FilmDetail
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Person
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.SeasonInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.Cache
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.io.IOException
import java.time.LocalDate
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/// Lenient JSON access so a missing or renamed field never crashes the app — it just shows less.
class J(val raw: Any?) {
    operator fun get(key: String): J = J((raw as? JSONObject)?.opt(key))
    val str: String? get() = when (raw) { is String -> raw.ifEmpty { null }; is Number -> raw.toString(); else -> null }
    val int: Int? get() = when (raw) { is Number -> raw.toInt(); is String -> raw.toIntOrNull(); else -> null }
    val double: Double? get() = when (raw) { is Number -> raw.toDouble(); is String -> raw.toDoubleOrNull(); else -> null }
    val bool: Boolean? get() = raw as? Boolean
    val array: List<J> get() = (raw as? JSONArray)?.let { a -> (0 until a.length()).map { J(a.opt(it)) } } ?: emptyList()
    val isNull: Boolean get() = raw == null || raw == JSONObject.NULL
}

class CatalogException(message: String) : IOException(message)

data class FilmArt(
    val logo: String? = null,
    val logoAspect: Double = 3.0,
    val poster: String? = null,      // textless poster
    val backdrop: String? = null,    // textless backdrop
)

data class WatchProvider(val id: Int, val name: String, val logo: String?) {
    /// Straight to the show on the service where we know how to search it; otherwise null.
    fun searchURL(title: String): String? {
        val q = java.net.URLEncoder.encode(title, "UTF-8")
        val n = name.lowercase()
        return when {
            "netflix" in n -> "https://www.netflix.com/search?q=$q"
            "amazon" in n || "prime" in n -> "https://www.primevideo.com/search/ref=atv_nb_sr?phrase=$q"
            "hotstar" in n -> "https://www.hotstar.com/in/explore?search_query=$q"
            "apple" in n -> "https://tv.apple.com/search?term=$q"
            "youtube" in n -> "https://www.youtube.com/results?search_query=$q"
            "zee5" in n -> "https://www.zee5.com/search?q=$q"
            "viki" in n -> "https://www.viki.com/search?q=$q"
            "iqiyi" in n -> "https://www.iq.com/search?query=$q"
            "mx player" in n -> "https://www.mxplayer.in/search?q=$q"
            else -> null
        }
    }
}

data class WatchProviders(
    val link: String? = null,
    val stream: List<WatchProvider> = emptyList(),
    val free: List<WatchProvider> = emptyList(),
    val rent: List<WatchProvider> = emptyList(),
    val buy: List<WatchProvider> = emptyList(),
) {
    val isEmpty get() = stream.isEmpty() && free.isEmpty() && rent.isEmpty() && buy.isEmpty()
}

/// The rows on Home. Each comes per category, or for all four mixed together.
enum class ShelfKind(val title: String) {
    POPULAR("Popular this week"),
    NEW("New & noteworthy"),
    AIRING("On air this week"),
    TOP("All-time greats");
}

data class Shelf(val kind: ShelfKind, val category: Category?) {
    val key: String get() = "${kind.name}-${category?.name ?: "ALL"}"
}

/// Drama genres you can browse. Romance isn't a TV genre on TMDB, so it goes by keyword.
data class DramaGenre(val name: String, val genreID: Int? = null, val keywords: String? = null)

/// Show data from TMDB (themoviedb.org). Only K-dramas, C-dramas, Thai dramas and Japanese dramas get through.
object Catalog {
    private lateinit var cacheDir: File

    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .cache(Cache(File(cacheDir, "http"), 256L shl 20))
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    fun init(context: Context) { cacheDir = context.cacheDir }

    val tmdbToken: String get() = Prefs.tmdbToken.ifBlank { BuildConfig.TMDB_TOKEN }.trim()
    val hasToken: Boolean get() = tmdbToken.isNotEmpty()

    fun setToken(t: String) {
        Prefs.putTmdbToken(t)
        shelfCache.clear()
    }

    private val detailCache = ConcurrentHashMap<String, FilmDetail>()
    private val shelfCache = ConcurrentHashMap<String, List<FilmRef>>()
    private val seasonCache = ConcurrentHashMap<String, List<Episode>>()
    private val artCache = ConcurrentHashMap<String, FilmArt>()
    private val trailerCache = ConcurrentHashMap<String, String>()
    private val providerCache = ConcurrentHashMap<String, WatchProviders>()

    // MARK: Public API

    suspend fun shelf(s: Shelf): List<FilmRef> {
        shelfCache[s.key]?.let { return it }
        val films = TMDB.shelf(s)
        if (films.isNotEmpty()) shelfCache[s.key] = films
        return films
    }

    fun cachedShelf(s: Shelf): List<FilmRef>? = shelfCache[s.key]

    suspend fun search(q: String): List<FilmRef> {
        val t = q.trim()
        if (t.isEmpty()) return emptyList()
        return TMDB.search(t)
    }

    suspend fun genre(g: DramaGenre, category: Category?): List<FilmRef> {
        val key = "genre-${g.name}-${category?.name}"
        shelfCache[key]?.let { return it }
        val films = TMDB.genre(g, category)
        if (films.isNotEmpty()) shelfCache[key] = films
        return films
    }

    suspend fun detail(id: String): FilmDetail {
        detailCache[id]?.let { return it }
        val d = TMDB.showDetail(id)
        detailCache[id] = d
        return d
    }

    fun cached(id: String): FilmDetail? = detailCache[id]

    /// Every episode in one season of a show.
    suspend fun season(showID: String, number: Int): List<Episode> {
        val key = "$showID|$number"
        seasonCache[key]?.let { return it }
        val eps = TMDB.season(showID, number)
        seasonCache[key] = eps
        return eps
    }

    fun cachedSeason(showID: String, number: Int): List<Episode>? = seasonCache["$showID|$number"]

    /// Textless poster/backdrop and the show's title logo, for Apple Music–style pages.
    suspend fun art(id: String): FilmArt? {
        val path = TMDB.path(id) ?: return null
        artCache[id]?.let { return it }
        val j = runCatching { TMDB.call("$path/images", mapOf("include_image_language" to "en,null")) }.getOrNull() ?: return null
        fun best(list: List<J>, lang: String?): J? = list.filter { it["iso_639_1"].str == lang }
            .sortedWith(compareByDescending<J> { it["vote_average"].double ?: 0.0 }.thenByDescending { it["vote_count"].double ?: 0.0 })
            .firstOrNull()
        val logos = j["logos"].array.filter { (it["file_path"].str ?: "").endsWith(".png") }
        val logo = colourfulLogo(logos) ?: best(logos, "en")
        val art = FilmArt(
            logo = TMDB.img(logo?.get("file_path")?.str, "w500"),
            logoAspect = logo?.get("aspect_ratio")?.double ?: 3.0,
            poster = TMDB.img(best(j["posters"].array, null)?.get("file_path")?.str, "original"),
            backdrop = TMDB.img(best(j["backdrops"].array, null)?.get("file_path")?.str, "w1280"),
        )
        artCache[id] = art
        return art
    }

    /// The YouTube key of the show's best trailer, if TMDB has one.
    suspend fun trailer(id: String): String? {
        val path = TMDB.path(id) ?: return null
        trailerCache[id]?.let { return it.ifEmpty { null } }
        val j = runCatching { TMDB.call("$path/videos", mapOf("include_video_language" to "en,ko,zh,th,ja,null")) }.getOrNull() ?: return null
        val vids = j["results"].array.filter { it["site"].str == "YouTube" && it["key"].str != null }
        fun rank(v: J): Int = (if (v["type"].str == "Trailer") 8 else if (v["type"].str == "Teaser") 4 else 0) +
            (if (v["official"].bool == true) 2 else 0) + (if (v["iso_639_1"].str == "en") 1 else 0)
        val best = vids.maxByOrNull(::rank)?.get("key")?.str
        trailerCache[id] = best ?: ""
        return best
    }

    /// Where the show streams, rents or sells in a country (India by default). Data from JustWatch via TMDB.
    suspend fun providers(id: String, region: String = "IN"): WatchProviders? {
        val path = TMDB.path(id) ?: return null
        val key = "$id|$region"
        providerCache[key]?.let { return it }
        val j = runCatching { TMDB.call("$path/watch/providers") }.getOrNull() ?: return null
        val r = j["results"][region]
        fun list(k: String): List<WatchProvider> = r[k].array.sortedBy { it["display_priority"].int ?: 99 }.mapNotNull { p ->
            val name = p["provider_name"].str ?: return@mapNotNull null
            WatchProvider(p["provider_id"].int ?: name.hashCode(), name, TMDB.img(p["logo_path"].str, "w154"))
        }
        val out = WatchProviders(r["link"].str, list("flatrate"), list("free") + list("ads"), list("rent"), list("buy"))
        providerCache[key] = out
        return out
    }

    /// Shows often have several logos on TMDB — a coloured original plus white and black versions.
    /// Prefer the coloured one: check the best-rated English logos (small thumbnails) and take the
    /// first that has real colour in it. null when every version is plain white or black.
    private suspend fun colourfulLogo(logos: List<J>): J? = coroutineScope {
        var english = logos.filter { it["iso_639_1"].str == "en" }
        if (english.isEmpty()) english = logos
        val ranked = english.sortedWith(compareByDescending<J> { it["vote_average"].double ?: 0.0 }.thenByDescending { it["vote_count"].double ?: 0.0 })
        val candidates = ranked.take(6)
        if (candidates.size <= 1) return@coroutineScope null
        val kinds = candidates.map { c ->
            async {
                val url = TMDB.img(c["file_path"].str, "w185") ?: return@async null
                Images.bitmap(url)?.let { Palette.logoInk(it) }
            }
        }.awaitAll()
        candidates.indices.firstOrNull { kinds[it] == Palette.LogoInk.COLOUR || kinds[it] == Palette.LogoInk.DARK_COLOUR }?.let { candidates[it] }
    }

    val genres = listOf(
        DramaGenre("Romance", keywords = "9840|9799"),
        DramaGenre("Comedy", 35),
        DramaGenre("Melodrama", 10766),
        DramaGenre("Mystery", 9648),
        DramaGenre("Crime", 80),
        DramaGenre("Action", 10759),
        DramaGenre("Fantasy", 10765),
        DramaGenre("Family", 10751),
        DramaGenre("History & politics", 10768),
    )
    val genreNames: List<String> get() = genres.map { it.name }
    fun genreNamed(name: String): DramaGenre? = genres.firstOrNull { it.name == name }

    // MARK: Networking

    suspend fun get(url: String, headers: Map<String, String> = emptyMap()): J = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url).header("Accept", "application/json").apply { headers.forEach { (k, v) -> header(k, v) } }.build()
        val resp = try { client.newCall(req).execute() } catch (e: IOException) { throw CatalogException("Couldn't reach TMDB. Check your connection.") }
        resp.use {
            if (!it.isSuccessful) throw CatalogException(
                if (it.code == 401) "TMDB didn't accept your token. Check it in Settings → Show data." else "TMDB answered with error ${it.code}."
            )
            val body = it.body?.string() ?: ""
            J(runCatching { JSONTokener(body).nextValue() }.getOrNull())
        }
    }
}

/// TMDB, which needs a free token.
object TMDB {
    private const val BASE = "https://api.themoviedb.org/3"

    fun img(p: String?, size: String): String? = if (p.isNullOrEmpty()) null else "https://image.tmdb.org/t/p/$size$p"

    /// Genres a show can't have and still count: animation, kids, news, reality, talk and documentaries.
    private const val EXCLUDED = "16,10762,10763,10764,10767,99"
    private val excludedIDs = EXCLUDED.split(",").map { it.toInt() }.toSet()

    /// TMDB's TV genres, as the names Matinee uses.
    val genreNames: Map<Int, String> = mapOf(
        35 to "Comedy", 80 to "Crime", 9648 to "Mystery", 10759 to "Action", 10765 to "Fantasy",
        10751 to "Family", 10766 to "Melodrama", 10768 to "History & politics", 18 to "Drama", 37 to "Western",
    )

    fun displayGenre(name: String): String = when (name) {
        "Action & Adventure" -> "Action"
        "Sci-Fi & Fantasy" -> "Fantasy"
        "War & Politics" -> "History & politics"
        "Soap" -> "Melodrama"
        else -> name
    }

    /// Accepts either a v4 "API Read Access Token" (long JWT) or a v3 API key.
    suspend fun call(path: String, q: Map<String, String> = emptyMap()): J {
        val token = Catalog.tmdbToken
        if (token.isEmpty()) throw CatalogException("Connect TMDB to load shows.")
        val params = q.toMutableMap()
        params["language"] = "en-US"
        val builder = "$BASE$path".toHttpUrl().newBuilder()
        if (token.length <= 40) params["api_key"] = token
        params.toSortedMap().forEach { (k, v) -> builder.addQueryParameter(k, v) }
        val headers = if (token.length > 40) mapOf("Authorization" to "Bearer $token") else emptyMap()
        return Catalog.get(builder.build().toString(), headers)
    }

    /// The API path for a show id: "/tv/1399".
    fun path(id: String): String? = if (id.startsWith(FilmRef.SHOW_PREFIX)) "/tv/" + id.removePrefix(FilmRef.SHOW_PREFIX) else null

    /// Only dramas from the four categories, and nothing animated, reality or talk.
    fun allowed(m: J): Boolean {
        val lang = m["original_language"].str ?: return false
        if (lang !in Category.allLangs) return false
        val ids = m["genre_ids"].array.mapNotNull { it.int } + m["genres"].array.mapNotNull { it["id"].int }
        return ids.none { it in excludedIDs }
    }

    fun showRef(m: J): FilmRef? {
        val id = m["id"].int ?: return null
        val name = m["name"].str ?: m["original_name"].str ?: return null
        val year = m["first_air_date"].str?.take(4)?.toIntOrNull()
        return FilmRef(FilmRef.SHOW_PREFIX + id, name, year, img(m["poster_path"].str, "w500"), img(m["backdrop_path"].str, "w1280"), m["original_language"].str)
    }

    fun episode(e: J, season: Int): Episode? {
        val n = e["episode_number"].int ?: return null
        return Episode(
            season = e["season_number"].int ?: season, number = n, name = e["name"].str ?: "Episode $n",
            overview = e["overview"].str, airDate = e["air_date"].str?.let { runCatching { LocalDate.parse(it) }.getOrNull() },
            runtime = e["runtime"].int, still = img(e["still_path"].str, "w780"), communityRating = e["vote_average"].double,
        )
    }

    /// Results that pass the category filter and have a poster.
    private fun refs(j: J): List<FilmRef> = j["results"].array.filter(::allowed).mapNotNull(::showRef).filter { it.poster != null }

    private val base = mapOf(
        "without_genres" to EXCLUDED,
        "with_type" to "2|4",                   // miniseries or scripted
        "include_adult" to "false",
        "include_null_first_air_dates" to "false",
    )

    /// One category, or all four with their results taking turns.
    suspend fun discover(category: Category?, q: Map<String, String>, voteFloor: (Category) -> Int = { 0 }): List<FilmRef> = coroutineScope {
        val cats = category?.let { listOf(it) } ?: Category.entries
        val lists = cats.map { c ->
            async {
                val params = base + q + mapOf("with_original_language" to c.primaryLang) +
                    (voteFloor(c).takeIf { it > 0 }?.let { mapOf("vote_count.gte" to it.toString()) } ?: emptyMap())
                runCatching { refs(call("/discover/tv", params)) }
            }
        }.awaitAll()
        if (lists.all { it.isFailure }) throw lists.first().exceptionOrNull()!!
        interleave(lists.map { it.getOrDefault(emptyList()) })
    }

    fun interleave(lists: List<List<FilmRef>>): List<FilmRef> {
        val out = ArrayList<FilmRef>()
        val seen = HashSet<String>()
        val longest = lists.maxOfOrNull { it.size } ?: 0
        for (i in 0 until longest) for (l in lists) if (i < l.size && seen.add(l[i].id)) out.add(l[i])
        return out
    }

    private fun topFloor(c: Category) = when (c) { Category.KDRAMA -> 200; Category.CDRAMA -> 40; Category.JDRAMA -> 40; Category.THAI -> 15 }

    suspend fun shelf(s: Shelf): List<FilmRef> {
        val today = LocalDate.now()
        return when (s.kind) {
            ShelfKind.POPULAR -> discover(s.category, mapOf("sort_by" to "popularity.desc", "first_air_date.gte" to today.minusYears(12).toString()), { 3 })
            ShelfKind.NEW -> discover(s.category, mapOf(
                "sort_by" to "popularity.desc",
                "first_air_date.gte" to today.minusDays(200).toString(),
                "first_air_date.lte" to today.toString(),
            ))
            ShelfKind.AIRING -> discover(s.category, mapOf(
                "sort_by" to "popularity.desc",
                "air_date.gte" to today.minusDays(7).toString(),
                "air_date.lte" to today.plusDays(7).toString(),
            ))
            ShelfKind.TOP -> discover(s.category, mapOf("sort_by" to "vote_average.desc"), ::topFloor)
        }
    }

    suspend fun genre(g: DramaGenre, category: Category?): List<FilmRef> {
        val q = mutableMapOf("sort_by" to "popularity.desc")
        g.genreID?.let { q["with_genres"] = it.toString() }
        g.keywords?.let { q["with_keywords"] = it }
        return discover(category, q, { 3 })
    }

    /// Shows in TMDB's order of relevance, kept to the four categories.
    suspend fun search(q: String): List<FilmRef> = coroutineScope {
        val pages = listOf(1, 2).map { p -> async { runCatching { call("/search/tv", mapOf("query" to q, "include_adult" to "false", "page" to p.toString())) } } }.awaitAll()
        if (pages.all { it.isFailure }) throw pages.first().exceptionOrNull()!!
        pages.mapNotNull { it.getOrNull() }.flatMap { j -> j["results"].array.filter(::allowed).mapNotNull(::showRef) }.distinctBy { it.id }
    }

    suspend fun recommendations(id: String): List<FilmRef> {
        val path = path(id) ?: return emptyList()
        return runCatching { refs(call("$path/recommendations")) }.getOrDefault(emptyList())
    }

    suspend fun discoverGenres(genres: List<String>): List<FilmRef> {
        val ids = genres.mapNotNull { n -> Catalog.genreNamed(n)?.genreID }.joinToString(",")
        if (ids.isEmpty()) return emptyList()
        return runCatching { discover(null, mapOf("with_genres" to ids, "sort_by" to "vote_average.desc"), { 30 }) }.getOrDefault(emptyList())
    }

    /// Cards for the taste quiz: well-known dramas from every category, each with its genre names.
    suspend fun deck(): List<Pair<FilmRef, List<String>>> = coroutineScope {
        val calls = Category.entries.flatMap { c ->
            listOf(
                mapOf("sort_by" to "vote_count.desc", "page" to "1"),
                mapOf("sort_by" to "popularity.desc", "page" to "1", "vote_count.gte" to "10"),
            ).map { q -> async { runCatching { call("/discover/tv", base + q + mapOf("with_original_language" to c.primaryLang)) }.getOrNull() } }
        } + async { runCatching { call("/discover/tv", base + mapOf("sort_by" to "vote_count.desc", "with_keywords" to "9840|9799", "with_original_language" to "ko")) }.getOrNull() }
        val pages = calls.awaitAll()
        val seen = HashSet<String>()
        val out = ArrayList<Pair<FilmRef, List<String>>>()
        pages.forEachIndexed { i, j ->
            val romance = i == pages.lastIndex
            for (m in j?.get("results")?.array ?: emptyList()) {
                if (!allowed(m)) continue
                val f = showRef(m) ?: continue
                if (f.poster == null || !seen.add(f.id)) continue
                val g = cardGenres(m) + if (romance) listOf("Romance") else emptyList()
                if (g.isNotEmpty()) out.add(f to g.distinct())
            }
        }
        // Spread genres out so the first cards aren't all one kind of show.
        val byGenre = out.shuffled().groupBy { it.second.first() }.mapValues { it.value.toMutableList() }.toSortedMap()
        val mixed = ArrayList<Pair<FilmRef, List<String>>>()
        while (mixed.size < out.size) {
            var progressed = false
            for (k in byGenre.keys) byGenre[k]?.takeIf { it.isNotEmpty() }?.let { mixed.add(it.removeAt(0)); progressed = true }
            if (!progressed) break
        }
        mixed.take(30)
    }

    /// The genres a quiz card counts towards. Everything here is a drama, so "Drama" itself doesn't.
    fun cardGenres(m: J): List<String> = m["genre_ids"].array.mapNotNull { it.int?.let(genreNames::get) }.filter { it != "Drama" && it != "Western" }

    /// Well-known dramas in the given genre, for the endless taste quiz.
    suspend fun deckPage(genre: String, page: Int): List<Pair<FilmRef, List<String>>> {
        val g = Catalog.genreNamed(genre)
        val q = mutableMapOf("sort_by" to "vote_count.desc", "page" to page.toString())
        g?.genreID?.let { q["with_genres"] = it.toString() }
        g?.keywords?.let { q["with_keywords"] = it }
        val c = Category.entries.random()
        val j = runCatching { call("/discover/tv", base + q + mapOf("with_original_language" to c.primaryLang)) }.getOrNull() ?: return emptyList()
        return j["results"].array.filter(::allowed).mapNotNull { m ->
            val f = showRef(m)?.takeIf { it.poster != null } ?: return@mapNotNull null
            val gs = (cardGenres(m) + if (g?.keywords != null) listOf(genre) else emptyList()).distinct()
            if (gs.isEmpty()) null else f to gs
        }
    }

    suspend fun showDetail(id: String): FilmDetail {
        val num = id.removePrefix(FilmRef.SHOW_PREFIX)
        // aggregate_credits covers every season; plain credits only lists the latest one.
        val m = call("/tv/$num", mapOf("append_to_response" to "aggregate_credits,recommendations"))
        val r = showRef(m) ?: throw CatalogException("TMDB answered with error 404.")
        return FilmDetail(
            ref = r,
            tagline = m["tagline"].str,
            overview = m["overview"].str,
            // Shows rarely give a single runtime; take the usual episode length, else the latest episode's.
            runtimeMinutes = m["episode_run_time"].array.firstNotNullOfOrNull { it.int } ?: m["last_episode_to_air"]["runtime"].int,
            genres = m["genres"].array.mapNotNull { it["name"].str?.let(::displayGenre) },
            creators = m["created_by"].array.mapNotNull { it["name"].str },
            networks = m["networks"].array.mapNotNull { it["name"].str },
            status = m["status"].str,
            lastYear = m["last_air_date"].str?.take(4)?.toIntOrNull(),
            cast = m["aggregate_credits"]["cast"].array.take(30).mapNotNull { c ->
                val pid = c["id"].int ?: return@mapNotNull null
                val name = c["name"].str ?: return@mapNotNull null
                Person("tmdbp-$pid", name, c["roles"].array.firstOrNull()?.get("character")?.str ?: "", img(c["profile_path"].str, "w185"))
            },
            communityRating = m["vote_average"].double,
            voteCount = m["vote_count"].int,
            countries = m["origin_country"].array.mapNotNull { it.str?.let { code -> Locale("", code).displayCountry.ifEmpty { null } } },
            seasons = m["seasons"].array.mapNotNull { s ->
                val n = s["season_number"].int ?: return@mapNotNull null
                SeasonInfo(n, s["name"].str ?: "Season $n", s["episode_count"].int ?: 0, s["air_date"].str?.take(4)?.toIntOrNull(),
                    img(s["poster_path"].str, "w500"), s["overview"].str)
            },
            nextEpisode = if (!m["next_episode_to_air"].isNull) episode(m["next_episode_to_air"], 0) else null,
            similar = refs(m["recommendations"]),
        )
    }

    suspend fun season(showID: String, number: Int): List<Episode> {
        val num = showID.removePrefix(FilmRef.SHOW_PREFIX)
        val j = call("/tv/$num/season/$number")
        return j["episodes"].array.mapNotNull { episode(it, number) }
    }
}
