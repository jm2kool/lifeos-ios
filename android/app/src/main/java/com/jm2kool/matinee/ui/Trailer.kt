package com.jm2kool.matinee.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.webkit.WebChromeClient
import android.webkit.WebView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

/// The trailer, full screen and playing straight away. Tap ✕ to go back to the show.
@Composable
fun TrailerView(key: String, title: String, onClose: () -> Unit) {
    val ctx = LocalContext.current
    BackHandler(onBack = onClose)
    Box(Modifier.fillMaxSize().background(Color.Black).clickableNoRipple { }) {
        YouTubePlayer(key, Modifier.fillMaxSize())
        Row(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(top = 8.dp, end = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            IconCircle(Icons.Filled.NorthEast, "Open in YouTube", 44.dp, Theme.chip) {
                runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/watch?v=$key"))) }
            }
            IconCircle(Icons.Filled.Close, "Close $title trailer", 44.dp, Theme.chip, onClick = onClose)
        }
    }
}

/// YouTube's embedded player. Loaded from an https base URL so YouTube sees a referrer
/// (without one, embeds refuse to play with "error 153").
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun YouTubePlayer(key: String, modifier: Modifier) {
    AndroidView(modifier = modifier, factory = { c ->
        WebView(c).apply {
            setBackgroundColor(android.graphics.Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            webChromeClient = WebChromeClient()
            val html = """
                <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
                <style>html,body{margin:0;height:100%;background:#000}
                .wrap{position:absolute;top:50%;left:0;width:100%;transform:translateY(-50%);aspect-ratio:16/9}
                iframe{width:100%;height:100%;border:0}</style></head><body><div class="wrap">
                <iframe src="https://www.youtube.com/embed/$key?autoplay=1&playsinline=1&rel=0&modestbranding=1&fs=1"
                allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
                referrerpolicy="strict-origin-when-cross-origin"></iframe></div></body></html>
            """.trimIndent()
            loadDataWithBaseURL("https://matinee.jm2kool.app", html, "text/html", "utf-8", null)
        }
    }, onRelease = { it.destroy() })
}
