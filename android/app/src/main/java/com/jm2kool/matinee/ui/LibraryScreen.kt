package com.jm2kool.matinee.ui

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Casino
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ViewCarousel
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.jm2kool.matinee.model.DramaFilter
import com.jm2kool.matinee.model.FilmList
import com.jm2kool.matinee.model.FilmRef
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.ui.Type.semibold

private val panes = listOf("Watchlist", "Shows", "Likes", "Lists")

@Composable
fun LibraryView() {
    val section = Prefs.librarySection.takeIf { it in panes } ?: "Watchlist"
    val d = Library.doc
    val glow: List<FilmRef> = when (section) {
        "Watchlist" -> d.watchlist.filter(Prefs.watchlistFilter::includes).take(3)
        "Shows" -> (Library.showsInProgress + Library.watchedFilms).take(3)
        "Likes" -> d.liked.asReversed().take(3)
        else -> d.lists.mapNotNull { it.films.firstOrNull() }
    }
    AmbientScreen(glow) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            LargeTitle("Library") {
                when (section) {
                    "Lists" -> IconCircle(Icons.Filled.Add, "New list", 38.dp, Theme.chip) { Router.sheet = SheetRoute.NewList(null) }
                    "Watchlist" -> if (d.watchlist.isNotEmpty()) WatchlistMenu()
                }
            }
            Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Segmented(panes, section, Modifier.padding(horizontal = 16.dp)) { Prefs.putLibrarySection(it) }
                when (section) {
                    "Watchlist" -> Watchlist()
                    "Shows" -> Shows()
                    "Likes" -> Likes()
                    else -> Lists()
                }
            }
            BottomSpace()
        }
    }
}

@Composable
private fun WatchlistMenu() {
    var open by remember { mutableStateOf(false) }
    Box {
        IconCircle(Icons.Filled.FilterList, "Sort and pick", 38.dp, Theme.chip) { open = true }
        DropdownMenu(open, { open = false }, containerColor = Color(0xFF1C1C1E)) {
            MenuItem("Recently added", if (!Prefs.watchlistSortByTitle) Icons.Filled.CheckCircle else null) { open = false; Prefs.putWatchlistSortByTitle(false) }
            MenuItem("Title", if (Prefs.watchlistSortByTitle) Icons.Filled.CheckCircle else null) { open = false; Prefs.putWatchlistSortByTitle(true) }
            MenuItem("Random pick", Icons.Filled.Casino) { open = false; Router.pickRandom(Prefs.watchlistFilter) }
        }
    }
}

/// An iOS-style segmented control, in plain colours.
@Composable
fun Segmented(options: List<String>, selected: String, modifier: Modifier = Modifier, onSelect: (String) -> Unit) {
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = 0.1f)).padding(2.dp)) {
        for (o in options) {
            val on = o == selected
            Box(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(if (on) Color.White.copy(alpha = 0.24f) else Color.Transparent)
                .clickable { if (!on) { Haptics.selection(); onSelect(o) } }.padding(vertical = 7.dp), contentAlignment = Alignment.Center) {
                Text(o, style = Type.footnote.semibold(), color = Color.White, maxLines = 1)
            }
        }
    }
}

@Composable
private fun Watchlist() {
    val all = Library.doc.watchlist.let { if (Prefs.watchlistSortByTitle) it.sortedBy { f -> f.title.lowercase() } else it }
    val media = Prefs.watchlistFilter
    val list = all.filter(media::includes)
    if (all.isNotEmpty()) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { DramaFilterBar(media) { Prefs.putWatchlistFilter(it) } }
    when {
        list.isEmpty() && all.isNotEmpty() -> EmptyState(Icons.Filled.LiveTv, "No ${media.category?.plural ?: "shows"} saved",
            "Tap the clock on any ${media.category?.label ?: "show"} to save it for later.", Modifier.padding(top = 30.dp))
        list.isEmpty() -> EmptyState(Icons.Filled.Schedule, "Nothing saved yet", "Tap the clock on any show to save it for later.", Modifier.padding(top = 40.dp))
        else -> {
            Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${list.size} ${if (list.size == 1) "show" else "shows"} to watch", style = Type.subheadline, color = Theme.dim, modifier = Modifier.weight(1f))
                Chip(prominent = true, onClick = { Router.pickRandom(media) }) { Label("Random pick", Icons.Filled.Casino) }
            }
            Text("Tip: shake your phone or double-tap Library for a random pick too.", style = Type.caption, color = Theme.dim, modifier = Modifier.padding(horizontal = 20.dp))
            PosterGrid(list, modifier = Modifier.padding(horizontal = 16.dp))
        }
    }
}

@Composable
private fun Shows() {
    val watching = Library.showsInProgress
    val finished = Library.watchedFilms
    if (watching.isEmpty() && finished.isEmpty()) {
        EmptyState(Icons.Filled.LiveTv, "No shows yet", "Tick off an episode on any show's page, or mark it watched, and it shows up here.", Modifier.padding(top = 40.dp))
        return
    }
    if (watching.isNotEmpty()) {
        Column {
            SectionHeader("Watching", if (watching.size == 1) "1 show" else "${watching.size} shows")
            ShowProgressRow(watching)
        }
    }
    if (finished.isNotEmpty()) {
        SectionHeader("Watched", if (finished.size == 1) "1 show" else "${finished.size} shows")
        PosterGrid(finished, modifier = Modifier.padding(horizontal = 16.dp)) { f ->
            Row(Modifier.height(14.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                SmallRating(Library.rating(f.id))
                Liked(Library.isLiked(f.id), 9.dp)
            }
        }
    }
}

@Composable
private fun Likes() {
    val list = Library.doc.liked.asReversed()
    if (list.isEmpty()) EmptyState(Icons.Filled.FavoriteBorder, "No likes yet", "Tap the heart on shows you love.", Modifier.padding(top = 40.dp))
    else PosterGrid(list, modifier = Modifier.padding(horizontal = 16.dp))
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Lists() {
    val lists = Library.doc.lists
    if (lists.isEmpty()) {
        EmptyState(Icons.AutoMirrored.Filled.List, "No lists yet", "Group shows however you like — a ranking, a binge plan, a mood.", Modifier.padding(top = 40.dp))
        PillButton("Create a list", Icons.Filled.Add, Modifier.padding(horizontal = 40.dp), prominent = true, size = ControlSize.LARGE, fill = true) { Router.sheet = SheetRoute.NewList(null) }
        return
    }
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (l in lists) {
            var menu by remember { mutableStateOf(false) }
            Box(Modifier.combinedClickable(onClick = { Router.push(ListRoute(l.id)) }, onLongClick = { Haptics.heavy(); menu = true })) {
                ListCard(l)
                DropdownMenu(menu, { menu = false }, containerColor = Color(0xFF1C1C1E)) {
                    MenuItem("Edit", Icons.Filled.Edit) { menu = false; Router.sheet = SheetRoute.EditList(l) }
                    MenuItem("Delete", Icons.Filled.Delete, destructive = true) { menu = false; Library.deleteList(l) }
                }
            }
        }
    }
}

/// Overlapping poster stack, like a fanned hand of cards.
@Composable
fun ListCard(list: FilmList) {
    Column(Modifier.fillMaxWidth().background(Theme.card, RoundedCornerShape(22.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.height(108.dp).fillMaxWidth()) {
            val films = list.films.take(5)
            for ((i, f) in films.withIndex().reversed()) {
                Box(Modifier.offset(x = (i * 52).dp).zIndex(-i.toFloat()).softShadow(6.dp, corner = 6.dp, alpha = 0.8f)) {
                    PosterView(f, width = 72.dp, corner = 6.dp, showTitleFallback = false, glows = false)
                }
            }
            if (films.isEmpty()) Box(Modifier.width(72.dp).height(108.dp).background(Theme.chip, RoundedCornerShape(6.dp)), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Add, null, tint = Theme.dim)
            }
        }
        Row(verticalAlignment = Alignment.Bottom) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(list.name, style = Type.headline, color = Color.White)
                if (list.note.isNotEmpty()) Text(list.note, style = Type.subheadline, color = Theme.dim, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text("${list.films.size} show${if (list.films.size == 1) "" else "s"}", style = Type.caption.semibold(), color = Theme.dim)
        }
    }
}

@Composable
fun ListDetailView(listID: String) {
    val list = Library.doc.lists.firstOrNull { it.id == listID }
    var editing by rememberSaveable { mutableStateOf(false) }
    val deck = Prefs.deckMode
    val ctx = LocalContext.current
    AmbientScreen(list?.films?.take(3) ?: emptyList()) {
        if (list == null) {
            Column { TopBar(); EmptyState(Icons.AutoMirrored.Filled.List, "List not found", "It may have been deleted.", Modifier.padding(top = 60.dp)) }
            return@AmbientScreen
        }
        if (deck && list.films.isNotEmpty() && !editing) {
            Column(Modifier.fillMaxSize()) {
                TopBar(list.name) { DeckToggle() }
                FilmDeckScreen(list.films, DeckAction.WATCHLIST)
            }
            return@AmbientScreen
        }
        Column(Modifier.fillMaxSize()) {
            TopBar(list.name) {
                if (list.films.isNotEmpty()) DeckToggle()
                BarButton(if (editing) "Done" else "Reorder", bold = editing) { editing = !editing }
                var menu by remember { mutableStateOf(false) }
                Box {
                    IconCircle(Icons.Filled.MoreHoriz, "More", 38.dp, Theme.chip) { menu = true }
                    DropdownMenu(menu, { menu = false }, containerColor = Color(0xFF1C1C1E)) {
                        MenuItem("Edit details", Icons.Filled.Edit) { menu = false; Router.sheet = SheetRoute.EditList(list) }
                        MenuItem("Share", Icons.Filled.Share) {
                            menu = false
                            ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shareText(list)), null))
                        }
                        MenuItem("Delete list", Icons.Filled.Delete, destructive = true) { menu = false; Library.deleteList(list); Router.pop() }
                    }
                }
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (list.note.isNotEmpty()) Text(list.note, style = Type.body, color = Color.White.copy(alpha = 0.8f))
                val seen = list.films.count { Library.isWatched(it.id) }
                if (list.films.isNotEmpty()) {
                    LinearProgressIndicator(progress = { seen.toFloat() / list.films.size }, color = Theme.watch, trackColor = Color.White.copy(alpha = 0.15f),
                        drawStopIndicator = {}, gapSize = 0.dp, modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape))
                    Text("You've seen $seen of ${list.films.size}", style = Type.caption, color = Theme.dim)
                }
                Spacer(Modifier.height(6.dp))
                for ((i, f) in list.films.withIndex()) {
                    Row(Modifier.fillMaxWidth().clickable(enabled = !editing) { Router.open(f) }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (editing) Icon(Icons.Filled.RemoveCircle, "Remove", tint = Color(0xFFFF453A), modifier = Modifier.size(24.dp).clickableNoRipple {
                            Library.updateList(list.copy(films = list.films.filterIndexed { k, _ -> k != i }))
                        })
                        if (list.ranked) Text("${i + 1}", style = Type.title3, color = Theme.dim, modifier = Modifier.width(30.dp))
                        PosterView(f, width = 44.dp, corner = 5.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(f.title, style = Type.body.semibold(), color = Color.White)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(f.yearText, style = Type.subheadline, color = Theme.dim)
                                if (Library.isWatched(f.id)) Icon(Icons.Filled.Visibility, null, tint = Theme.watch, modifier = Modifier.size(15.dp))
                                SmallRating(Library.rating(f.id))
                            }
                        }
                        if (editing) {
                            Icon(Icons.Filled.KeyboardArrowUp, "Move up", tint = if (i > 0) Color.White else Theme.dim, modifier = Modifier.size(30.dp).clickableNoRipple(i > 0) {
                                Library.updateList(list.copy(films = list.films.toMutableList().apply { add(i - 1, removeAt(i)) }))
                            })
                            Icon(Icons.Filled.KeyboardArrowDown, "Move down", tint = if (i < list.films.lastIndex) Color.White else Theme.dim,
                                modifier = Modifier.size(30.dp).clickableNoRipple(i < list.films.lastIndex) {
                                    Library.updateList(list.copy(films = list.films.toMutableList().apply { add(i + 1, removeAt(i)) }))
                                })
                        }
                    }
                }
                BottomSpace(40.dp)
            }
        }
    }
}

/// Toolbar button to flip between the swipe deck and the normal list.
@Composable
fun DeckToggle() {
    IconCircle(if (Prefs.deckMode) Icons.Filled.GridView else Icons.Filled.ViewCarousel, if (Prefs.deckMode) "List view" else "Swipe", 38.dp, Theme.chip) {
        Prefs.putDeckMode(!Prefs.deckMode)
    }
}

private fun shareText(list: FilmList): String = (listOf(list.name) + list.films.mapIndexed { i, f ->
    "${if (list.ranked) "${i + 1}." else "•"} ${f.title} (${f.yearText})"
}).joinToString("\n")

@Composable
fun ListEditor(seed: FilmRef? = null, editing: FilmList? = null) {
    val dismiss = LocalDismiss.current
    var name by rememberSaveable { mutableStateOf(editing?.name ?: "") }
    var note by rememberSaveable { mutableStateOf(editing?.note ?: "") }
    var ranked by rememberSaveable { mutableStateOf(editing?.ranked ?: false) }
    Column(Modifier.fillMaxSize().background(Theme.bg).imePadding()) {
        SheetBar(if (editing == null) "New list" else "Edit list", leading = { CloseButton() }, trailing = {
            SaveButton(name.isNotBlank()) {
                val n = name.trim()
                if (editing != null) Library.updateList(editing.copy(name = n, note = note, ranked = ranked))
                else Library.createList(n, note, ranked, seed)
                dismiss()
            }
        })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            FormGroup {
                FormField(name, { name = it }, "List name")
                Hairline(Modifier.padding(start = 16.dp))
                FormField(note, { note = it }, "Description (optional)", singleLine = false)
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                FormGroup { ToggleRow("Ranked list", ranked) { ranked = it } }
                Text("Ranked lists show numbers and keep the order you set.", style = Type.footnote, color = Theme.dim, modifier = Modifier.padding(horizontal = 16.dp))
            }
            if (seed != null) FormGroup { Label("Starts with ${seed.title}", Icons.Filled.LiveTv, modifier = Modifier.padding(16.dp)) }
        }
    }
}

@Composable
fun AddToListSheet(film: FilmRef) {
    Column(Modifier.fillMaxSize().background(Theme.bg)) {
        SheetBar("Add to list", trailing = { SaveButton { Router.sheet = null } })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormGroup {
                Row(Modifier.fillMaxWidth().clickable { Router.sheet = SheetRoute.NewList(film) }.padding(16.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.AddCircle, null, tint = Theme.accent)
                    Text("New list with this show", style = Type.body, color = Theme.accent)
                }
                for (l in Library.doc.lists) {
                    Hairline(Modifier.padding(start = 16.dp))
                    val on = l.films.any { it.id == film.id }
                    Row(Modifier.fillMaxWidth().clickable { Library.toggle(film, l) }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(l.name, style = Type.body, color = Color.White)
                            Text("${l.films.size} shows", style = Type.caption, color = Theme.dim)
                        }
                        Icon(if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, tint = if (on) Theme.accent else Theme.dim, modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
    }
}

// MARK: - Form pieces (what iOS draws as a grouped Form)

@Composable
fun FormGroup(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.card)) { content() }
}

@Composable
fun FormHeader(text: String) {
    Text(text.uppercase(), style = Type.footnote, color = Theme.dim, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
}

@Composable
fun FormFooter(text: String) {
    Text(text, style = Type.footnote, color = Theme.dim, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

@Composable
fun FormField(value: String, onChange: (String) -> Unit, placeholder: String, singleLine: Boolean = true, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp)) {
        if (value.isEmpty()) Text(placeholder, style = Type.body, color = Theme.dim)
        BasicTextField(value, onChange, singleLine = singleLine, maxLines = if (singleLine) 1 else 5, textStyle = Type.body.copy(color = Color.White),
            cursorBrush = SolidColor(Theme.accent), modifier = Modifier.fillMaxWidth())
    }
}

@Composable
fun ToggleRow(title: String, on: Boolean, tint: Color = Theme.accent, icon: androidx.compose.ui.graphics.vector.ImageVector? = null, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!on) }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Label(title, icon, modifier = Modifier.weight(1f), maxLines = 2)
        Switch(on, onChange, colors = SwitchDefaults.colors(checkedTrackColor = tint, checkedThumbColor = Color.White, uncheckedTrackColor = Color.White.copy(alpha = 0.16f),
            uncheckedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent))
    }
}
