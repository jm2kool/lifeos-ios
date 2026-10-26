package com.jm2kool.matinee.ui

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.jm2kool.matinee.BuildConfig
import com.jm2kool.matinee.data.Catalog
import com.jm2kool.matinee.model.Library
import com.jm2kool.matinee.model.LibraryDoc
import com.jm2kool.matinee.model.Prefs
import com.jm2kool.matinee.model.RatingStyle
import com.jm2kool.matinee.model.Toast
import java.io.File

@Composable
fun SettingsView() {
    val ctx = LocalContext.current
    var tmdb by rememberSaveable { mutableStateOf(Prefs.tmdbToken) }
    var confirmErase by remember { mutableStateOf(false) }
    val restore = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching { ctx.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() } }.getOrNull()
        if (text == null || !Library.importJSON(text)) Library.toast = Toast("That file isn't a Matinee backup", Icons.Outlined.Restore)
    }
    Column(Modifier.fillMaxSize().background(Theme.bg).imePadding()) {
        SheetBar("Settings", trailing = { SaveButton(onClick = LocalDismiss.current) })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(26.dp)) {
            Column {
                FormHeader("Account")
                FormGroup { Text("Matinee keeps everything on this phone — no account, no sign-in.", style = Type.footnote, color = Theme.dim, modifier = Modifier.padding(16.dp)) }
            }
            Column {
                FormHeader("Show data")
                FormGroup {
                    Row(Modifier.fillMaxWidth().padding(16.dp)) {
                        Text("TMDB", style = Type.body, color = Color.White, modifier = Modifier.weight(1f))
                        Text(if (Catalog.hasToken) "Connected" else "Not connected", style = Type.body, color = Theme.dim)
                    }
                    Hairline(Modifier.padding(start = 16.dp))
                    Box(Modifier.fillMaxWidth().padding(16.dp)) {
                        if (tmdb.isEmpty()) Text(if (BuildConfig.TMDB_TOKEN.isNotEmpty()) "Built-in token (paste one to replace it)" else "TMDB API read access token", style = Type.body, color = Theme.dim)
                        BasicTextField(tmdb, { tmdb = it }, singleLine = true, textStyle = Type.body.copy(color = Color.White), cursorBrush = SolidColor(Theme.accent),
                            visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
                    }
                    Hairline(Modifier.padding(start = 16.dp))
                    Text("Save token", style = Type.body, color = Theme.accent, modifier = Modifier.fillMaxWidth().clickable {
                        Catalog.setToken(tmdb)
                        Library.toast = Toast(if (Catalog.hasToken) "TMDB connected" else "TMDB token removed", Icons.Filled.Star)
                    }.padding(16.dp))
                }
                FormFooter("Shows, posters and cast come from TMDB. Get a free API Read Access Token at themoviedb.org → Settings → API and paste it here.")
            }
            Column {
                FormHeader("Profile")
                FormGroup {
                    Row(Modifier.fillMaxWidth().clickable { Router.sheet = SheetRoute.EditFavorites }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Label("Edit favourites", Icons.Filled.Star, modifier = Modifier.weight(1f))
                        Text("${Library.favorites.size} of ${LibraryDoc.MAX_FAVORITES}", style = Type.body, color = Theme.dim)
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Theme.dim)
                    }
                }
                FormFooter("Up to eight shows on your profile. Reorder, add or remove them here.")
            }
            Column {
                FormHeader("Ratings")
                FormGroup(Modifier.padding(0.dp)) {
                    Box(Modifier.padding(12.dp)) {
                        Segmented(listOf("Score 1–100", "Stars 1–5"), if (Prefs.ratingStyle == RatingStyle.SCORE) "Score 1–100" else "Stars 1–5") {
                            Prefs.putRatingStyle(if (it.startsWith("Score")) RatingStyle.SCORE else RatingStyle.STARS)
                        }
                    }
                }
                FormFooter("Ratings are kept as a score out of 100, so you can switch any time. In stars, each half star is 10 points (★★★★ = 80).")
            }
            Column {
                FormHeader("Your data")
                FormGroup {
                    Row(Modifier.fillMaxWidth().clickable { exportLibrary(ctx) }.padding(16.dp)) { Label("Export my library (backup)", Icons.Filled.Upload, color = Theme.accent) }
                    Hairline(Modifier.padding(start = 16.dp))
                    Row(Modifier.fillMaxWidth().clickable { restore.launch(arrayOf("application/json", "text/plain", "*/*")) }.padding(16.dp)) {
                        Label("Restore from a backup…", Icons.Filled.Download, color = Theme.accent)
                    }
                }
                FormFooter("Everything lives on this phone. Export a backup now and then (save it to Drive or send it to yourself) so a new phone can pick up where this one left off.")
            }
            Column {
                FormGroup {
                    Row(Modifier.fillMaxWidth().clickable { confirmErase = true }.padding(16.dp)) { Label("Erase library", Icons.Outlined.Delete, color = Color(0xFFFF453A)) }
                }
                FormFooter("Matinee ${BuildConfig.VERSION_NAME} · A diary for K-dramas, C-dramas, Thai and Japanese dramas.")
            }
        }
    }
    if (confirmErase) AlertDialog(
        onDismissRequest = { confirmErase = false },
        title = { Text("Erase your whole library?") },
        text = { Text("Diary, ratings, likes, watchlist and lists will be removed. You can undo right after.") },
        confirmButton = { BarButton("Erase everything", Color(0xFFFF453A), bold = true) { confirmErase = false; Library.eraseAll() } },
        dismissButton = { BarButton("Cancel") { confirmErase = false } },
        containerColor = Color(0xFF1C1C1E), titleContentColor = Color.White, textContentColor = Color.White.copy(alpha = 0.8f),
    )
}

private fun exportLibrary(ctx: android.content.Context) {
    val dir = File(ctx.cacheDir, "shared").apply { mkdirs() }
    val f = File(dir, "matinee-library.json")
    f.writeText(Library.exportJSON())
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", f)
    val send = Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    ctx.startActivity(Intent.createChooser(send, "Export library"))
}
