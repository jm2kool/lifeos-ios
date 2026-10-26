package com.jm2kool.matinee.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jm2kool.matinee.model.DramaFilter
import com.jm2kool.matinee.model.Dates
import com.jm2kool.matinee.model.Episode
import com.jm2kool.matinee.model.Intermission
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Mood
import com.jm2kool.matinee.model.WatchSession
import com.jm2kool.matinee.model.Watching
import com.jm2kool.matinee.model.filmClock
import com.jm2kool.matinee.ui.Type.heavy
import com.jm2kool.matinee.ui.Type.semibold
import com.jm2kool.matinee.ui.Type.tracking
import kotlin.math.floor
import kotlin.math.min

/// Finishing an episode ticks it off.
private fun finish(s: WatchSession) {
    if (s.season != null && s.episode != null) Library.setSeen(s.film, listOf(Episode(s.season, s.episode, s.episodeTitle ?: "")), true)
    Watching.end(s.id)
    Haptics.success()
}

/// Floating bar above the tab bar while an episode is in progress.
@Composable
fun NowWatchingBar(session: WatchSession) {
    val now by tickingNow(1000)
    val elapsed = session.elapsed(now)
    val over = session.isProbablyOver(now)
    Box(Modifier.padding(horizontal = 16.dp).fillMaxWidth().softShadow(16.dp, 4.dp, 30.dp, 0.5f).clip(CircleShape).background(Color(0xFF242426)).border(0.5.dp, Theme.line, CircleShape)) {
        Row(Modifier.padding(start = 10.dp, end = 6.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.weight(1f).clickableNoRipple { Router.open(session.film) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                PosterView(session.film, width = 34.dp, corner = 5.dp, showTitleFallback = false, glows = false)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(session.title, style = Type.subheadline.semibold(), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val total = session.runtime?.let { " of ${filmClock(it)}" } ?: ""
                    val sub = when {
                        over -> "Credits rolling? Tap ✓ to tick it off"
                        session.running -> "Watching · ${filmClock(elapsed)}$total"
                        else -> "${session.lastStop?.mood?.let { "$it " } ?: ""}Intermission at ${filmClock(elapsed)}$total"
                    }
                    Text(sub, style = Type.caption, color = Theme.dim, maxLines = 1)
                }
            }
            val (icon, label, action) = when {
                session.running && !over -> Triple(Icons.Filled.Pause, "Intermission") { Router.sheet = SheetRoute.IntermissionOf(session.id) }
                over -> Triple(Icons.Filled.Check, "Tick it off") { finish(session) }
                else -> Triple(Icons.Filled.PlayArrow, "Resume") { Watching.resume(session.id) }
            }
            Box(Modifier.size(40.dp).clip(CircleShape).background(Theme.accent).clickable(onClick = action), contentAlignment = Alignment.Center) {
                Icon(icon, label, tint = Color.White, modifier = Modifier.size(18.dp))
            }
        }
        session.progress(now)?.let { p ->
            Box(Modifier.align(Alignment.BottomStart).padding(horizontal = 22.dp).padding(bottom = 1.dp).fillMaxWidth(p.toFloat().coerceAtLeast(0.02f)).height(2.5.dp)
                .clip(CircleShape).background(Theme.accent))
        }
    }
}

/// Pause an episode: confirm where you are, pick a mood, leave yourself a note.
@Composable
fun IntermissionSheet(sessionID: String) {
    val dismiss = LocalDismiss.current
    val s = Watching.sessions.firstOrNull { it.id == sessionID }
    if (s == null) {
        Column(Modifier.fillMaxSize().background(Theme.bg)) {
            SheetBar("", leading = { CloseButton() })
            EmptyState(Icons.Filled.LiveTv, "Nothing playing", "Start watching an episode from its show's page.", Modifier.padding(top = 60.dp))
        }
        return
    }
    var position by rememberSaveable { mutableDoubleStateOf(s.runtime?.let { min(floor(s.elapsed() / 60) * 60, it) } ?: (floor(s.elapsed() / 60) * 60)) }
    var mood by rememberSaveable { mutableStateOf(s.lastStop?.mood ?: "🤔") }
    var note by rememberSaveable { mutableStateOf("") }
    fun label(t: String) = t.uppercase()

    Column(Modifier.fillMaxSize().background(Theme.bg).imePadding()) {
        SheetBar("", leading = { BarButton("Keep watching") { dismiss() } })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                PosterView(s.film, width = 64.dp, corner = 6.dp)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("INTERMISSION", style = Type.caption.heavy().tracking(1.4f), color = Theme.accent)
                    Text(s.title, style = Type.title3, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text("Started ${Dates.relative(s.started)}", style = Type.caption, color = Theme.dim)
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(label("You stopped at"), style = Type.caption.heavy().tracking(1.2f), color = Theme.dim)
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val secs = position.toInt() % 60
                    Text(filmClock(position) + if (secs == 0) "" else " ${secs}s", style = Type.largeTitle.copy(fontSize = 44.sp, lineHeight = 50.sp), color = Color.White)
                    s.runtime?.let { Text("of ${filmClock(it)}", style = Type.body, color = Theme.dim, modifier = Modifier.padding(bottom = 8.dp)) }
                }
                val r = s.runtime
                if (r != null) Slider(position.toFloat(), { position = (Math.round(it / 60f) * 60.0).coerceIn(0.0, r) }, valueRange = 0f..r.toFloat(),
                    colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Theme.accent, inactiveTrackColor = Color.White.copy(alpha = 0.15f)))
                else Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    RoundButton(Icons.Filled.Remove, 40.dp, Color.White, "Back a minute") { position = (position - 60).coerceAtLeast(0.0) }
                    RoundButton(Icons.Filled.Add, 40.dp, Color.White, "On a minute") { position = (position + 60).coerceAtMost(6 * 3600.0) }
                }
                ExactTimeField(position, s.runtime ?: 6 * 3600.0) { position = it }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(label("How's it going?"), style = Type.caption.heavy().tracking(1.2f), color = Theme.dim)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(Mood.all) { (emoji, text) ->
                        val on = mood == emoji
                        Column(Modifier.size(74.dp).clip(RoundedCornerShape(18.dp)).background(if (on) Theme.accent.copy(alpha = 0.35f) else Theme.card)
                            .border(1.5.dp, if (on) Theme.accent else Color.Transparent, RoundedCornerShape(18.dp))
                            .clickable { mood = emoji; Haptics.selection() }, horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                            Text(emoji, fontSize = 28.sp)
                            Text(text, style = Type.caption2.semibold(), color = if (on) Color.White else Theme.dim, maxLines = 1)
                        }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(label("Where were you?"), style = Type.caption.heavy().tracking(1.2f), color = Theme.dim)
                Box(Modifier.fillMaxWidth().background(Theme.card, RoundedCornerShape(16.dp)).padding(14.dp)) {
                    if (note.isEmpty()) Text("e.g. right after the rooftop confession", style = Type.body, color = Theme.dim)
                    BasicTextField(note, { note = it }, maxLines = 4, textStyle = Type.body.copy(color = Color.White), cursorBrush = SolidColor(Theme.accent), modifier = Modifier.fillMaxWidth())
                }
                Text("Future you will thank you when you come back to it.", style = Type.caption, color = Theme.dim)
            }

            if (s.stops.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(label("Earlier stops"), style = Type.caption.heavy().tracking(1.2f), color = Theme.dim)
                for (stop in s.stops.asReversed()) IntermissionRow(stop)
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                PillButton("Pause here", Icons.Filled.Pause, prominent = true, size = ControlSize.LARGE, fill = true) {
                    Watching.intermission(sessionID, position, mood, note); Haptics.success(); dismiss()
                }
                PillButton("I finished it — tick it off", Icons.Filled.Check, size = ControlSize.LARGE, fill = true) { finish(s); dismiss() }
                Text("Stop tracking this episode", style = Type.footnote.semibold(), color = Color(0xFFFF453A),
                    modifier = Modifier.padding(top = 4.dp).clickable { Watching.end(s.id); dismiss() }.padding(8.dp))
            }
        }
    }
}

/// Type the exact time you stopped at — hours, minutes and seconds — instead of dragging.
@Composable
fun ExactTimeField(position: Double, limit: Double, onChange: (Double) -> Unit) {
    val t = Math.round(position).toInt()
    var h by remember { mutableStateOf("") }
    var m by remember { mutableStateOf("") }
    var sec by remember { mutableStateOf("") }
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(position, focused) {
        if (!focused) { h = (t / 3600).toString(); m = String.format("%02d", t % 3600 / 60); sec = String.format("%02d", t % 60) }
    }
    fun commit() {
        val total = ((h.toIntOrNull() ?: 0) * 3600 + min(59, m.toIntOrNull() ?: 0) * 60 + min(59, sec.toIntOrNull() ?: 0)).toDouble()
        onChange(total.coerceIn(0.0, limit))
    }
    @Composable
    fun box(v: String, placeholder: String, set: (String) -> Unit) {
        Box(Modifier.width(46.dp).height(38.dp).background(Theme.card, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            if (v.isEmpty()) Text(placeholder, style = Type.body, color = Theme.dim)
            BasicTextField(v, { n -> set(n.filter { it.isDigit() }.take(2)); commit() }, singleLine = true,
                textStyle = Type.body.copy(color = Color.White, textAlign = TextAlign.Center), cursorBrush = SolidColor(Theme.accent),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused })
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Filled.Keyboard, null, tint = Theme.dim, modifier = Modifier.size(18.dp))
        Text("Exact time", style = Type.subheadline.semibold(), color = Theme.dim)
        Spacer(Modifier.weight(1f))
        box(h, "h") { h = it }
        Text(":", color = Theme.dim)
        box(m, "mm") { m = it }
        Text(":", color = Theme.dim)
        box(sec, "ss") { sec = it }
    }
}

@Composable
fun IntermissionRow(stop: Intermission) {
    Row(Modifier.fillMaxWidth().background(Theme.card, RoundedCornerShape(14.dp)).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stop.mood, fontSize = 22.sp)
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("${filmClock(stop.at)} · ${Mood.label(stop.mood)}", style = Type.subheadline.semibold(), color = Color.White)
            if (stop.note.isNotEmpty()) Text("“${stop.note}”", style = Type.subheadline, color = Color.White.copy(alpha = 0.8f))
            Text(Dates.relative(stop.`when`), style = Type.caption, color = Theme.dim)
        }
    }
}

/// Home shelf of episodes you paused, each with your note so you remember where you were.
@Composable
fun IntermissionShelf(media: DramaFilter = DramaFilter.ALL) {
    val paused = Watching.paused.filter { media.includes(it.film) }
    if (paused.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionHeader("Intermission", "Pick up where you left off")
        LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(paused, key = { it.id }) { s ->
                Row(Modifier.width(300.dp).height(190.dp).background(Theme.card, RoundedCornerShape(22.dp)).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.clickableNoRipple { Router.open(s.film) }) { PosterView(s.film, width = 74.dp, corner = 8.dp) }
                    Column(Modifier.fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(s.title, style = Type.headline, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("Stopped at ${filmClock(s.banked)}${s.runtime?.let { " of ${filmClock(it)}" } ?: ""}", style = Type.caption.semibold(), color = Theme.dim)
                        s.lastStop?.let { stop ->
                            Text("${stop.mood} ${if (stop.note.isEmpty()) Mood.label(stop.mood) else "“${stop.note}”"}", style = Type.subheadline, color = Color.White.copy(alpha = 0.85f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(Dates.relative(stop.`when`), style = Type.caption2, color = Theme.dim)
                        }
                        Spacer(Modifier.weight(1f))
                        s.progress()?.let { p ->
                            LinearProgressIndicator(progress = { p.toFloat() }, color = Theme.accent, trackColor = Color.White.copy(alpha = 0.15f), drawStopIndicator = {}, gapSize = 0.dp,
                                modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape))
                        }
                        Chip(prominent = true, onClick = { Watching.resume(s.id) }) { Label("Resume", Icons.Filled.PlayArrow) }
                    }
                }
            }
        }
    }
}
