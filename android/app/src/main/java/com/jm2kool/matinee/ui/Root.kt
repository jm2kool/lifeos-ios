package com.jm2kool.matinee.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CollectionsBookmark
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.jm2kool.matinee.data.Taste
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.Watching
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/// Closes the sheet the content is showing in.
val LocalDismiss = staticCompositionLocalOf<() -> Unit> { { Router.sheet = null } }

@Composable
fun RootView() {
    val holder = rememberSaveableStateHolder()
    BackHandler(Router.sheet == null && (Router.randomDeck != null || Router.trailer != null || Router.stack.isNotEmpty() || Router.tab != AppTab.HOME)) {
        when {
            Router.trailer != null -> Router.trailer = null
            Router.randomDeck != null -> Router.closeRandom()
            Router.stack.isNotEmpty() -> Router.pop()
            else -> Router.tab = AppTab.HOME
        }
    }

    Box(Modifier.fillMaxSize().background(Theme.bg)) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                val tab = Router.tab
                val stack = Router.stacks.getValue(tab)
                val top = stack.lastOrNull()
                AnimatedContent(
                    targetState = Triple(tab, top, stack.size),
                    transitionSpec = {
                        val (t0, _, n0) = initialState
                        val (t1, _, n1) = targetState
                        when {
                            t0 != t1 || Router.randomPickOpening -> fadeIn(tween(160)) togetherWith fadeOut(tween(120))
                            n1 > n0 -> slideInHorizontally(tween(300)) { it } togetherWith slideOutHorizontally(tween(300)) { -it / 4 } + fadeOut(tween(300))
                            else -> slideInHorizontally(tween(300)) { -it / 4 } + fadeIn(tween(200)) togetherWith slideOutHorizontally(tween(300)) { it }
                        }
                    },
                    label = "nav",
                ) { (t, route, n) ->
                    holder.SaveableStateProvider("${t.name}/${route?.key ?: "root"}/$n") {
                        Box(Modifier.fillMaxSize().background(Theme.bg)) {
                            if (route == null) TabRoot(t) else RouteScreen(route)
                        }
                    }
                }
            }
            TabBar()
        }

        // Intermission mode: a "now watching" bar floats above the tab bar while an episode is playing.
        val current = Watching.current
        AnimatedVisibility(
            current != null && current.running && Router.randomDeck == null,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 92.dp),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut(),
        ) { current?.let { NowWatchingBar(it) } }

        // Shake (or double-tap Library) for a deck of random picks from your watchlist.
        AnimatedVisibility(Router.randomDeck != null, enter = fadeIn(tween(250)), exit = fadeOut(tween(300))) {
            Router.randomDeck?.let { deck -> RandomPickDeck(deck) { Router.closeRandom() } }
        }

        Router.trailer?.let { (k, title) -> TrailerView(k, title) { Router.trailer = null } }

        val toast = Library.toast
        AnimatedVisibility(
            toast != null, modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 4.dp),
            enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut(),
        ) {
            toast?.let { t ->
                ToastView(t) { Library.undo() }
                LaunchedEffect(t.id) {
                    delay(if (t.undo) 4000 else 2200)
                    if (Library.toast?.id == t.id) Library.toast = null
                }
            }
        }

        SheetHost()

        if (Taste.showQuiz) TasteQuizView { Taste.showQuiz = false }

        AnimatedVisibility(Router.showSplash, enter = fadeIn(), exit = fadeOut(tween(250))) {
            SplashView {
                Router.showSplash = false
                // The taste quiz waits until the opening titles finish.
                if (Taste.shouldOffer) Taste.showQuiz = true
            }
        }
    }
}

@Composable
private fun TabRoot(t: AppTab) = when (t) {
    AppTab.HOME -> HomeView()
    AppTab.DIARY -> DiaryView()
    AppTab.LIBRARY -> LibraryView()
    AppTab.PROFILE -> ProfileView()
    AppTab.SEARCH -> SearchView()
}

@Composable
private fun RouteScreen(r: Route) = when (r) {
    is ShowRoute -> ShowView(r.film)
    is ListRoute -> ListDetailView(r.id)
    is GenreRoute -> GenreView(r.name)
    is CollectionRoute -> CollectionView(r.kind)
}

@Composable
private fun TabBar() {
    NavigationBar(containerColor = Color(0xFF0B0B0C), tonalElevation = 0.dp, windowInsets = WindowInsets.navigationBars) {
        @Composable
        fun item(t: AppTab, label: String, on: ImageVector, off: ImageVector) {
            val selected = Router.tab == t
            NavigationBarItem(
                selected = selected,
                onClick = { Router.select(t) },
                icon = { Icon(if (selected) on else off, label) },
                label = { Text(label, style = Type.caption2.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium)) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = Theme.accent, selectedTextColor = Theme.accent,
                    unselectedIconColor = Color.White.copy(alpha = 0.6f), unselectedTextColor = Color.White.copy(alpha = 0.6f),
                    indicatorColor = Theme.accent.copy(alpha = 0.16f),
                ),
            )
        }
        item(AppTab.HOME, "Shows", Icons.Filled.LiveTv, Icons.Outlined.LiveTv)
        item(AppTab.DIARY, "Diary", Icons.AutoMirrored.Filled.MenuBook, Icons.AutoMirrored.Outlined.MenuBook)
        item(AppTab.LIBRARY, "Library", Icons.Filled.CollectionsBookmark, Icons.Outlined.CollectionsBookmark)
        item(AppTab.PROFILE, "Profile", Icons.Filled.AccountCircle, Icons.Outlined.AccountCircle)
        item(AppTab.SEARCH, "Search", Icons.Filled.Search, Icons.Filled.Search)
    }
}

/// Every sheet in the app, as a bottom sheet over the page.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SheetHost() {
    val route = Router.sheet ?: return
    key(route) {
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val scope = rememberCoroutineScope()
        val dismiss: () -> Unit = {
            scope.launch { state.hide() }.invokeOnCompletion { if (Router.sheet == route) Router.sheet = null }
        }
        ModalBottomSheet(
            onDismissRequest = { if (Router.sheet == route) Router.sheet = null },
            sheetState = state,
            containerColor = Color.Black,
            scrimColor = Color.Black.copy(alpha = 0.55f),
            shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
            dragHandle = null,
            contentWindowInsets = { WindowInsets(0) },
        ) {
            CompositionLocalProvider(LocalDismiss provides dismiss) {
                Box(Modifier.fillMaxHeight(if (route.isMedium) 0.62f else 0.94f)) { SheetContent(route) }
            }
        }
    }
}

private val SheetRoute.isMedium get() = this is SheetRoute.AddToList || this is SheetRoute.NewList || this is SheetRoute.EditList

@Composable
private fun SheetContent(route: SheetRoute) = when (route) {
    is SheetRoute.Log -> LogSheet(route.film, route.existing)
    is SheetRoute.AddToList -> AddToListSheet(route.film)
    is SheetRoute.NewList -> ListEditor(seed = route.film)
    is SheetRoute.EditList -> ListEditor(editing = route.list)
    SheetRoute.EditFavorites -> FavoritesEditor()
    SheetRoute.EditProfile -> ProfileEditor()
    SheetRoute.Settings -> SettingsView()
    SheetRoute.QuickLog -> QuickLogSheet()
    is SheetRoute.IntermissionOf -> IntermissionSheet(route.sessionID)
    is SheetRoute.EpisodeOf -> EpisodeSheet(route.show, route.episode)
    is SheetRoute.Wrap -> SeriesWrapSheet(route.show)
}

/// The little grabber at the top of every sheet.
@Composable
fun DragIndicator() {
    Box(Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.width(36.dp).height(5.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.3f)))
    }
}

/// A sheet's toolbar: a close or cancel on the left, the title, and the main action on the right.
@Composable
fun SheetBar(
    title: String,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    Column {
        DragIndicator()
        Box(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 12.dp)) {
            Box(Modifier.align(Alignment.CenterStart)) { leading?.invoke() }
            Text(title, style = Type.headline, color = Color.White, modifier = Modifier.align(Alignment.Center))
            Box(Modifier.align(Alignment.CenterEnd)) { trailing?.invoke() }
        }
    }
}

/// The circle ✕ that closes a sheet.
@Composable
fun CloseButton(onClick: () -> Unit = LocalDismiss.current) {
    IconCircle(Icons.Filled.Close, "Close", size = 34.dp, background = Theme.chip, onClick = onClick)
}

/// The accent ✓ that saves a sheet.
@Composable
fun SaveButton(enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.size(width = 64.dp, height = 34.dp).clip(CircleShape).background(if (enabled) Theme.accent else Theme.chip)
            .clickableNoRipple(enabled, onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Filled.Check, "Save", tint = Color.White.copy(alpha = if (enabled) 1f else 0.4f), modifier = Modifier.size(20.dp)) }
}

fun Modifier.clickableNoRipple(enabled: Boolean = true, onClick: () -> Unit) = composed {
    clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, enabled = enabled, onClick = onClick)
}

/// A page's own top bar: back, a title, and actions. Sits over the page, under the status bar.
@Composable
fun TopBar(title: String = "", onBack: (() -> Unit)? = { Router.pop() }, overImage: Boolean = false, actions: @Composable () -> Unit = {}) {
    Box(Modifier.fillMaxWidth().statusBarsPadding().height(52.dp).padding(horizontal = 12.dp)) {
        if (onBack != null) Box(Modifier.align(Alignment.CenterStart)) {
            IconCircle(Icons.AutoMirrored.Filled.ArrowBack, "Back", size = 38.dp,
                background = if (overImage) Color.Black.copy(alpha = 0.35f) else Theme.chip, onClick = onBack)
        }
        if (title.isNotEmpty()) Text(title, style = Type.headline, color = Color.White, maxLines = 1,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 56.dp))
        Box(Modifier.align(Alignment.CenterEnd)) {
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { actions() }
        }
    }
}

/// A big left-aligned title for the top of a tab, like iOS large titles.
@Composable
fun LargeTitle(title: String, actions: @Composable () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().statusBarsPadding()) {
        Box(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 12.dp)) {
            Box(Modifier.align(Alignment.CenterEnd)) {
                androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { actions() }
            }
        }
        Text(title, style = Type.largeTitle, color = Color.White, modifier = Modifier.padding(horizontal = 20.dp))
        Spacer(Modifier.height(6.dp))
    }
}

/// Room for the tab bar's gesture area at the bottom of a scrolling page.
@Composable
fun BottomSpace(extra: androidx.compose.ui.unit.Dp = 24.dp) {
    Spacer(Modifier.height(extra))
    Spacer(Modifier.windowInsetsBottomHeight(WindowInsets(0)))
}
