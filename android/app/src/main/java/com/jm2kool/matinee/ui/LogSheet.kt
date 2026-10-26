package com.jm2kool.matinee.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.outlined.Weekend
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.data.FilmArt
import com.jm2kool.matinee.data.Palette
import com.jm2kool.matinee.data.PosterPalette
import com.jm2kool.matinee.data.largePoster
import com.jm2kool.matinee.model.Dates
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.LogEntry
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.RatingStyle
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/// Log a viewing: when, how much you liked it, and what you thought — all on one screen.
/// Scored out of 100 on a dial, or in stars if that's what you picked in Settings.
/// Comfort shows skip the rating altogether.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogSheet(film: FilmRef, existing: LogEntry?) {
    val dismiss = LocalDismiss.current
    val earlier = Library.entries(film.id).filter { it.id != existing?.id }
    var date by rememberSaveable { mutableStateOf(existing?.watchedOn ?: System.currentTimeMillis()) }
    var rating by rememberSaveable { mutableStateOf(existing?.rating ?: if (existing == null) Library.rating(film.id) else null) }
    var liked by rememberSaveable { mutableStateOf(existing?.liked ?: Library.isLiked(film.id)) }
    var rewatch by rememberSaveable { mutableStateOf(existing?.rewatch ?: earlier.isNotEmpty()) }
    var review by rememberSaveable { mutableStateOf(existing?.review ?: "") }
    var tags by rememberSaveable { mutableStateOf(existing?.tags ?: emptyList()) }
    var tagDraft by rememberSaveable { mutableStateOf("") }
    var showCalendar by rememberSaveable { mutableStateOf(false) }
    var comfort by rememberSaveable { mutableStateOf(Library.isComfort(film.id)) }
    var art by remember { mutableStateOf<FilmArt?>(null) }
    var artLoaded by remember { mutableStateOf(false) }
    var palette by remember { mutableStateOf<PosterPalette?>(Palette.cached(film.largePoster ?: film.poster)) }

    LaunchedEffect(film.id) {
        art = Catalog.art(film.id)
        artLoaded = true
        if (palette == null) palette = Palette.of(art?.poster ?: film.largePoster ?: film.poster)
    }
    /// The sheet is painted in the show's accent colour, like its page.
    val bg by animateColorAsState(palette?.background ?: Color.Black, tween(500), label = "bg")
    val surface = palette?.surface ?: Theme.card
    val glow = palette?.glow
    val stars = Prefs.ratingStyle == RatingStyle.STARS
    val isCustomDate = !Dates.isToday(date) && !Dates.isYesterday(date)

    fun addTag() {
        val t = tagDraft.trim().lowercase().replace("#", "")
        if (t.isNotEmpty() && t !in tags) tags = tags + t
        tagDraft = ""
    }
    fun save() {
        addTag()
        Library.setComfort(film, comfort)
        val e = (existing ?: LogEntry(film = film)).copy(watchedOn = date, rating = if (comfort) null else rating, liked = liked, rewatch = rewatch,
            review = review.trim(), tags = tags)
        Library.log(e)
        if (!liked && Library.isLiked(film.id)) Library.toggleLike(film)
        Haptics.success()
        dismiss()
    }

    Box(Modifier.fillMaxSize().background(bg)) {
        // A soft glow from the poster behind the logo.
        if (glow != null) Canvas(Modifier.fillMaxWidth().height(380.dp)) {
            drawCircle(Brush.radialGradient(listOf(glow.copy(alpha = 0.45f), Color.Transparent), center = Offset(size.width / 2, 0f), radius = size.width * 0.85f),
                size.width * 0.85f, Offset(size.width / 2, 0f))
        }
        Column(Modifier.fillMaxSize().imePadding()) {
            SheetBar(if (existing != null) "Edit entry" else "Log show", leading = { CloseButton() }, trailing = { SaveButton { save() } })
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                // The show's logo, big, as the heading.
                Column(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    TitleArt(film.title, art?.logo, Modifier.heightIn(min = 80.dp), aspect = art?.logoAspect ?: 3.0, maxWidth = 280.dp, maxHeight = 110.dp, fontSize = 34f, ready = artLoaded)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(listOfNotNull(film.yearText.ifEmpty { null }, film.category?.label).joinToString(" · "), style = Type.subheadline.semibold(), color = Color.White.copy(alpha = 0.75f))
                        if (earlier.isNotEmpty() && existing == null) {
                            Text("·", style = Type.subheadline, color = Color.White.copy(alpha = 0.75f))
                            Label("Seen before", Icons.Filled.Repeat, color = Theme.watch, iconSize = 15.dp)
                        }
                    }
                }

                // When
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SheetLabel("Watched")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DateChip("Today", Dates.isToday(date), Modifier.weight(1f)) { date = System.currentTimeMillis(); showCalendar = false }
                        DateChip("Yesterday", Dates.isYesterday(date), Modifier.weight(1f)) { date = System.currentTimeMillis() - 86_400_000; showCalendar = false }
                        DateChip(if (isCustomDate) Dates.dayMonth(Dates.localDate(date)) else "Pick date", isCustomDate || showCalendar, Modifier.weight(1f)) { showCalendar = !showCalendar }
                    }
                    AnimatedVisibility(showCalendar) {
                        val state = rememberDatePickerState(
                            initialSelectedDateMillis = Dates.localDate(date).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
                            selectableDates = object : SelectableDates {
                                override fun isSelectableDate(utcTimeMillis: Long) = !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isAfter(LocalDate.now())
                            },
                        )
                        LaunchedEffect(state.selectedDateMillis) {
                            state.selectedDateMillis?.let { utc ->
                                val d = Instant.ofEpochMilli(utc).atZone(ZoneOffset.UTC).toLocalDate()
                                if (d != Dates.localDate(date)) date = Dates.startOfDay(d) + 12 * 3_600_000L
                            }
                        }
                        DatePicker(state, title = null, headline = null, showModeToggle = false,
                            colors = DatePickerDefaults.colors(containerColor = Color.Transparent, selectedDayContainerColor = Theme.accent, todayDateBorderColor = Theme.accent,
                                todayContentColor = Theme.accent, dayContentColor = Color.White, weekdayContentColor = Theme.dim, navigationContentColor = Color.White,
                                yearContentColor = Color.White, currentYearContentColor = Theme.accent, selectedYearContainerColor = Theme.accent,
                                subheadContentColor = Color.White, disabledDayContentColor = Color.White.copy(alpha = 0.25f)),
                            modifier = Modifier.fillMaxWidth().background(surface, RoundedCornerShape(20.dp)).padding(8.dp))
                    }
                }

                // Rating + like
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SheetLabel(if (comfort) "Comfort watch" else if (stars) "Rating" else "Score")
                    when {
                        comfort -> Row(verticalAlignment = Alignment.Top) {
                            Text("No rating needed — it's a comfort show. Just log that you watched it.", style = Type.subheadline, color = Color.White.copy(alpha = 0.7f), modifier = Modifier.weight(1f))
                            LikeButton(liked) { liked = !liked }
                        }
                        stars -> Row(verticalAlignment = Alignment.Top) {
                            FilmRatingInput(rating, starSize = 34.dp) { rating = it }
                            Spacer(Modifier.weight(1f))
                            LikeButton(liked) { liked = !liked }
                        }
                        else -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                            FilmRatingInput(rating, dialSize = 210.dp) { rating = it }
                            Box(Modifier.align(Alignment.TopEnd)) { LikeButton(liked) { liked = !liked } }
                        }
                    }
                    ToggleRow("Comfort show — don't ask me to rate it", comfort, Theme.star, if (comfort) Icons.Filled.Weekend else Icons.Outlined.Weekend) { comfort = it }
                }

                ToggleRow("I've seen this before", rewatch, Theme.watch, Icons.Filled.Repeat) { rewatch = it }

                // Review
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SheetLabel("Review")
                    Box(Modifier.fillMaxWidth().heightIn(min = 110.dp).background(surface, RoundedCornerShape(18.dp)).padding(14.dp)) {
                        if (review.isEmpty()) Text("What did you think?", style = Type.body, color = Theme.dim)
                        BasicTextField(review, { review = it }, textStyle = Type.body.copy(color = Color.White), cursorBrush = SolidColor(Theme.accent),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences), modifier = Modifier.fillMaxWidth())
                    }
                }

                // Tags
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SheetLabel("Tags")
                    if (tags.isNotEmpty()) ChipRow(padding = 0.dp, spacing = 6.dp) {
                        for (t in tags) Row(Modifier.clip(CircleShape).background(Theme.accent.copy(alpha = 0.18f)).clickable { tags = tags - t }.padding(horizontal = 10.dp, vertical = 6.dp),
                            horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("#$t", style = Type.footnote.semibold(), color = Theme.accent)
                            Icon(Icons.Filled.Close, null, tint = Theme.accent, modifier = Modifier.size(12.dp))
                        }
                    }
                    Row(Modifier.fillMaxWidth().background(surface, RoundedCornerShape(18.dp)).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) {
                            if (tagDraft.isEmpty()) Text("Add a tag (who with, where…)", style = Type.body, color = Theme.dim)
                            BasicTextField(tagDraft, { tagDraft = it }, singleLine = true, textStyle = Type.body.copy(color = Color.White), cursorBrush = SolidColor(Theme.accent),
                                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, imeAction = ImeAction.Done),
                                keyboardActions = KeyboardActions(onDone = { addTag() }), modifier = Modifier.fillMaxWidth())
                        }
                        if (tagDraft.isNotEmpty()) BarButton("Add", bold = true) { addTag() }
                    }
                    val suggestions = Library.allTags.filter { it !in tags && (tagDraft.isEmpty() || it.startsWith(tagDraft.lowercase())) }
                    if (suggestions.isNotEmpty()) ChipRow(padding = 0.dp) {
                        for (t in suggestions.take(10)) PillButton("#$t", size = ControlSize.SMALL) { tags = tags + t; tagDraft = "" }
                    }
                }

                if (existing != null) {
                    PillButton("Delete this entry", Icons.Filled.Delete, size = ControlSize.LARGE, fill = true, color = Color(0xFFFF453A)) { Library.delete(existing); dismiss() }
                }
                Spacer(Modifier.height(30.dp))
            }
        }
    }
}

@Composable
private fun SheetLabel(t: String) = Text(t.uppercase(), style = Type.caption.heavy().tracking(1.2f), color = Color.White.copy(alpha = 0.65f))

@Composable
private fun DateChip(t: String, on: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.clip(CircleShape).background(if (on) Theme.accent.copy(alpha = 0.3f) else Theme.chip).border(1.5.dp, if (on) Theme.accent else Color.Transparent, CircleShape)
        .clickable(onClick = onClick).padding(vertical = 13.dp), contentAlignment = Alignment.Center) {
        Text(t, style = Type.subheadline.semibold(), color = Color.White, textAlign = TextAlign.Center, maxLines = 1)
    }
}

@Composable
private fun LikeButton(liked: Boolean, onClick: () -> Unit) {
    val scale = remember { Animatable(1f) }
    LaunchedEffect(liked) { if (liked) { scale.animateTo(1.3f, tween(110)); scale.animateTo(1f, tween(160)) } }
    Icon(if (liked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, if (liked) "Liked" else "Like",
        tint = if (liked) Theme.heart else Color.White.copy(alpha = 0.5f),
        modifier = Modifier.size(34.dp).graphicsLayer { scaleX = scale.value; scaleY = scale.value }.clickableNoRipple { onClick(); Haptics.medium() })
}
