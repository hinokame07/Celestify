package com.music.spotui.ui.immersive.lyrics

import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.*
import androidx.annotation.Keep
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

internal data class CinemaBounds(val lyrics: Rect, val media: Rect)

private const val ORIGIN = "https://appassets.androidplatform.net"
private const val STAGE = "/assets/spicy-cinema/"

@Keep
private class StageBridge(
    val dispatch: (String, Float) -> Unit,
    val resize: (CinemaBounds) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var connected = true

    fun disconnect() {
        connected = false
        main.removeCallbacksAndMessages(null)
    }

    @JavascriptInterface
    fun action(name: String, value: Double) {
        if (value.isFinite())
            main.post {
                if (connected)
                    dispatch(
                        name,
                        (if (name == "lyricSeek") value.coerceIn(0.0, 86400000.0)
                            else value.coerceIn(0.0, 1.0))
                            .toFloat(),
                    )
            }
    }

    @JavascriptInterface
    fun layout(json: String) {
        val a = runCatching { JSONArray(json) }.getOrNull() ?: return
        if (a.length() != 8 || (0 until 8).any { !a.optDouble(it).isFinite() }) return
        fun rect(i: Int): Rect {
            val x = a.getDouble(i).toFloat().coerceIn(0f, 1f)
            val y = a.getDouble(i + 1).toFloat().coerceIn(0f, 1f)
            return Rect(
                x,
                y,
                (x + a.getDouble(i + 2).toFloat()).coerceIn(x, 1f),
                (y + a.getDouble(i + 3).toFloat()).coerceIn(y, 1f),
            )
        }
        val result = CinemaBounds(rect(0), rect(4))
        main.post { if (connected) resize(result) }
    }
}

/**
 * One renderer per open lyric panel. Moving it between the player and dialog keeps the DOM, scroll
 * anchor, WebGL context and virtualizer alive. Never share the Spotify WebView.
 */
internal class CinemaSession {
    var dispatch: (String, Float) -> Unit = { _, _ -> }
    var bounds by mutableStateOf<CinemaBounds?>(null)
    var loaded by mutableStateOf(false)
    var unavailable by mutableStateOf(false)
    var web: WebView? = null
    val sent = mutableMapOf<String, String>()
    private val bridge = StageBridge({ n, v -> dispatch(n, v) }, { bounds = it })

    fun dispose() {
        bridge.disconnect()
        web?.let {
            (it.parent as? android.view.ViewGroup)?.removeView(it)
            it.removeJavascriptInterface("Cinema")
            it.destroy()
        }
        web = null
        sent.clear()
    }

    fun mount(context: android.content.Context): WebView {
        web?.let {
            return it
        }
        val loader =
            WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
                .addPathHandler("/res/", WebViewAssetLoader.ResourcesPathHandler(context))
                .build()
        return WebView(context)
            .apply {
                setBackgroundColor(Color.TRANSPARENT)
                settings.javaScriptEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mediaPlaybackRequiresUserGesture = false
                webViewClient =
                    object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView,
                            request: WebResourceRequest,
                        ): Boolean {
                            val uri = request.url
                            if (
                                request.hasGesture() &&
                                    request.isForMainFrame &&
                                    uri.scheme == "https" &&
                                    uri.host in
                                        setOf(
                                            "spicylyrics.org",
                                            "www.spicylyrics.org",
                                            "github.com",
                                            "unison.boidu.dev",
                                        )
                            ) {
                                val intent =
                                    android.content.Intent(android.content.Intent.ACTION_VIEW, uri)
                                runCatching { view.context.startActivity(intent) }
                            }
                            return true
                        }

                        override fun shouldInterceptRequest(
                            view: WebView,
                            request: WebResourceRequest,
                        ): WebResourceResponse? {
                            val url: Uri = request.url
                            if (
                                url.scheme == "https" &&
                                    url.host == "appassets.androidplatform.net" &&
                                    (url.path.orEmpty().startsWith(STAGE) ||
                                        url.path == "/res/font/inter.ttf")
                            )
                                loader.shouldInterceptRequest(url)?.let {
                                    return it
                                }
                            val host = url.host.orEmpty()
                            if (
                                !request.isForMainFrame &&
                                    url.scheme == "https" &&
                                    (host.endsWith(".scdn.co") || host.endsWith(".spotifycdn.com"))
                            )
                                return null
                            return WebResourceResponse(
                                "text/plain",
                                "utf-8",
                                403,
                                "Forbidden",
                                emptyMap(),
                                null,
                            )
                        }

                        override fun onPageFinished(view: WebView, url: String) {
                            if (url == ORIGIN + STAGE + "index.html") {
                                view.evaluateJavascript("typeof window.stage === 'object'") {
                                    loaded = it == "true"
                                    unavailable = !loaded
                                }
                            }
                        }

                        override fun onRenderProcessGone(
                            view: WebView,
                            detail: RenderProcessGoneDetail,
                        ): Boolean {
                            loaded = false
                            unavailable = true
                            (view.parent as? android.view.ViewGroup)?.removeView(view)
                            if (web === view) web = null
                            view.destroy()
                            return true
                        }
                    }
                addJavascriptInterface(bridge, "Cinema")
                loadUrl(ORIGIN + STAGE + "index.html")
            }
            .also { web = it }
    }

    fun send(method: String, json: String) {
        if (loaded && sent[method] != json) {
            sent[method] = json
            web?.evaluateJavascript("window.stage?.$method($json)", null)
        }
    }
}

internal val LocalCinemaSession =
    staticCompositionLocalOf<CinemaSession> { error("Spicy panel missing") }

@Composable
internal fun CinemaSurface(
    model: String,
    image: String,
    artistImage: String,
    document: String?,
    visible: Boolean,
    onBounds: (CinemaBounds) -> Unit,
    progress: () -> String,
    onAction: (String, Float) -> Unit,
) {
    val session = LocalCinemaSession.current
    val clock by rememberUpdatedState(progress)
    SideEffect { session.dispatch = onAction }
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            android.widget.FrameLayout(ctx).apply {
                val view = session.mount(ctx)
                (view.parent as? android.view.ViewGroup)?.removeView(view)
                addView(view, android.widget.FrameLayout.LayoutParams(-1, -1))
            }
        },
        onRelease = { it.removeAllViews() },
    )
    LaunchedEffect(session.bounds) { session.bounds?.let(onBounds) }
    LaunchedEffect(session.loaded, model) { session.send("setSong", model) }
    LaunchedEffect(session.loaded, image) { session.send("cover", JSONObject.quote(image)) }
    LaunchedEffect(session.loaded, artistImage) {
        session.send("artist", JSONObject.quote(artistImage))
    }
    LaunchedEffect(session.loaded, document) { session.send("setLyrics", document ?: "null") }
    LaunchedEffect(session.loaded, visible) {
        if (!session.loaded) return@LaunchedEffect
        val stage = session.web ?: return@LaunchedEffect
        if (visible) stage.onResume() else stage.onPause()
        stage.evaluateJavascript("window.stage?.visible($visible)", null)
        if (!visible) return@LaunchedEffect
        while (true) {
            stage.evaluateJavascript("window.stage?.tick(" + clock() + ")", null)
            delay(160)
        }
    }
}
