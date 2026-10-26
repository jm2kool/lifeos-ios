package com.jm2kool.matinee.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jm2kool.matinee.model.Dates
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.LogEntry
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.RatingStyle
import com.jm2kool.matinee.model.Score
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import java.time.LocalDate
import java.util.Locale
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun DiaryView() {
    var filter by rememberSaveable { mutableStateOf("") }
    val all = Library.entries
    val q = filter.lowercase().replace("#", "")
    val grouped = remember(all, q) {
        all.filter { q.isEmpty() || it.film.title.contains(q, ignoreCase = true) || q in it.tags }
            .groupBy { Dates.monthYear(it.watchedOn) }.toList()
    }
    AmbientScreen(all.take(3).map { it.film }) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 40.dp)) {
            item {
                LargeTitle("Diary") { IconCircle(Icons.Filled.Add, "Log a show", 38.dp, Theme.chip) { Router.sheet = SheetRoute.QuickLog } }
            }
            if (all.isEmpty()) {
                item {
                    Column(Modifier.padding(top = 60.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        EmptyState(Icons.AutoMirrored.Filled.MenuBook, "Your diary is empty", "Log a show and it lands here with the date, your rating and your review.")
                        PillButton("Log your first show", Icons.Filled.Add, Modifier.padding(horizontal = 40.dp), prominent = true, size = ControlSize.LARGE, fill = true) {
                            Router.sheet = SheetRoute.QuickLog
                        }
                    }
                }
            } else {
                item { SearchField(filter, { filter = it }, "Filter by title or #tag", Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) }
                item { YearSummary(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
                for ((month, entries) in grouped) {
                    item(key = "h-$month") {
                        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 4.dp), verticalAlignment = Alignment.Bottom) {
                            Text(month, style = Type.headline, color = Color.White)
                            Spacer(Modifier.weight(1f))
                            Text("${entries.size} show${if (entries.size == 1) "" else "s"}", style = Type.caption, color = Theme.dim)
                        }
                    }
                    items(entries, key = { it.id }) { e -> SwipeableDiaryRow(e) }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SwipeableDiaryRow(e: LogEntry) {
    var menu by remember { mutableStateOf(false) }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { v ->
        when (v) {
            SwipeToDismissBoxValue.EndToStart -> { Library.delete(e); true }
            SwipeToDismissBoxValue.StartToEnd -> { Router.sheet = SheetRoute.Log(e.film, null); false }
            else -> false
        }
    }, positionalThreshold = { it * 0.35f })
    SwipeToDismissBox(
        state,
        backgroundContent = {
            val toStart = state.dismissDirection == SwipeToDismissBoxValue.EndToStart
            Box(Modifier.fillMaxSize().background(if (toStart) Color(0xFFFF453A) else Theme.watch).padding(horizontal = 24.dp),
                contentAlignment = if (toStart) Alignment.CenterEnd else Alignment.CenterStart) {
                Icon(if (toStart) Icons.Filled.Delete else Icons.Filled.Repeat, if (toStart) "Delete" else "Log again", tint = Color.White)
            }
        },
    ) {
        Box(Modifier.background(Color.Black).combinedClickable(onClick = { Router.open(e.film) }, onLongClick = { Haptics.heavy(); menu = true })) {
            DiaryRow(e)
            DropdownMenu(menu, { menu = false }, containerColor = Color(0xFF1C1C1E)) {
                MenuItem("Edit entry", Icons.Filled.Edit) { menu = false; Router.sheet = SheetRoute.Log(e.film, e) }
                MenuItem("Log again", Icons.Filled.Repeat) { menu = false; Router.sheet = SheetRoute.Log(e.film, null) }
                MenuItem("Delete", Icons.Filled.Delete, destructive = true) { menu = false; Library.delete(e) }
            }
        }
    }
    Hairline(Modifier.padding(start = 74.dp))
}

@Composable
fun DiaryRow(entry: LogEntry) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.width(40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(Dates.dayNumber(entry.watchedOn), style = Type.title2.copy(fontSize = 24.sp), color = Color.White)
            Text(Dates.weekdayShort(entry.watchedOn).uppercase(), style = Type.caption2.semibold(), color = Theme.dim)
        }
        PosterView(entry.film, width = 46.dp, corner = 5.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(entry.film.title, style = Type.body.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Text(entry.film.yearText, style = Type.subheadline, color = Theme.dim)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SmallRating(entry.rating)
                Liked(entry.liked)
                if (entry.rewatch) Icon(Icons.Filled.Repeat, null, tint = Theme.watch, modifier = Modifier.size(13.dp))
                if (entry.review.isNotEmpty()) Icon(Icons.AutoMirrored.Filled.Notes, null, tint = Theme.dim, modifier = Modifier.size(13.dp))
                entry.film.category?.let { Text(it.flag, style = Type.caption) }
                for (t in entry.tags.take(2)) Text("#$t", style = Type.caption, color = Theme.accent)
            }
        }
    }
}

/// This year at a glance, with a GitHub-style heatmap of drama nights.
@Composable
fun YearSummary(modifier: Modifier = Modifier) {
    val year = LocalDate.now().year
    val d = Library.doc
    val thisYear = d.entries.filter { Dates.year(it.watchedOn) == year }
    val rated = thisYear.mapNotNull { it.rating }
    // Episodes count when you ticked them off.
    val episodes = d.shows.values.sumOf { p -> p.seen.values.count { Dates.year(it) == year } }
    Column(modifier.fillMaxWidth().panel(RoundedCornerShape(26.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("$year SO FAR", style = Type.caption.heavy().tracking(1.2f), color = Theme.dim)
        Row(Modifier.fillMaxWidth()) {
            Stat("${thisYear.map { it.film.id }.distinct().size}", "shows")
            Stat("$episodes", "episodes")
            Stat("${thisYear.count { it.liked }}", "liked")
            if (Prefs.ratingStyle == RatingStyle.STARS) Stat(if (rated.isEmpty()) "–" else String.format(Locale.US, "%.1f", Score.toStars(rated.average())), "avg ★")
            else Stat(if (rated.isEmpty()) "–" else rated.average().roundToInt().toString(), "avg score")
        }
        val dates = d.entries.map { it.watchedOn } + d.shows.values.flatMap { it.seen.values }
        Heatmap(dates)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Stat(v: String, l: String) {
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(v, style = Type.title2.copy(fontSize = 26.sp), color = Color.White)
        Text(l, style = Type.caption, color = Theme.dim)
    }
}

@Composable
fun Heatmap(dates: List<Long>, weeks: Int = 26) {
    val counts = remember(dates) { dates.groupingBy { Dates.localDate(it) }.eachCount() }
    val today = LocalDate.now()
    val weekdayToday = today.dayOfWeek.value % 7          // Sunday first, like the iPhone calendar
    val start = today.minusDays(((weeks - 1) * 7 + weekdayToday).toLong())
    Canvas(Modifier.fillMaxWidth().height((7 * 11 + 6 * 3).dp)) {
        val gap = 3.dp.toPx()
        val cell = min((size.width - gap * (weeks - 1)) / weeks, (size.height - gap * 6) / 7)
        for (w in 0 until weeks) for (dd in 0 until 7) {
            val day = start.plusDays((w * 7 + dd).toLong())
            if (day.isAfter(today)) continue
            val n = counts[day] ?: 0
            val c = if (n == 0) Color.White.copy(alpha = 0.07f) else if (n == 1) Theme.accent.copy(alpha = 0.55f) else Theme.accent
            drawRoundRect(c, Offset(w * (cell + gap), dd * (cell + gap)), Size(cell, cell), CornerRadius(2.5.dp.toPx()))
        }
    }
}

/// A rounded search box, like the one iOS puts under a title.
@Composable
fun SearchField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, onSubmit: () -> Unit = {}) {
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = 0.12f)).padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.Search, null, tint = Theme.dim, modifier = Modifier.size(20.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, style = Type.body, color = Theme.dim, maxLines = 1)
            BasicTextField(value, onChange, singleLine = true, textStyle = Type.body.copy(color = Color.White), cursorBrush = SolidColor(Theme.accent),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Search),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { onSubmit() }),
                modifier = Modifier.fillMaxWidth())
        }
        if (value.isNotEmpty()) Icon(Icons.Filled.Cancel, "Clear", tint = Theme.dim, modifier = Modifier.size(18.dp).clickableNoRipple { onChange("") })
    }
}
