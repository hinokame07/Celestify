package com.music.spotui.ui.immersive.lyrics

import android.graphics.Bitmap
import android.util.LruCache
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.bumptech.glide.Glide
import com.music.spotui.data.preferences.AtmospherePref
import com.music.spotui.ui.look.rememberReduceMotion
import com.tx24.spicyplayer.lyrics.spicy.canvas.StackBlur
import kotlinx.coroutines.*

private data class BackdropArt(val bitmap: Bitmap, val mean: Color)

private val blurredCovers = LruCache<String, BackdropArt>(16)

/**
 * One full-window drawing, including the areas under the system bars. All content/insets are
 * siblings.
 */
@Composable
internal fun SpicyBackdrop(
    cover: String,
    artist: String,
    playing: Boolean,
    modifier: Modifier = Modifier,
    coverSource: Boolean = false,
) {
    val pref = StagePreference
    val style = when {
        !AtmospherePref.dynamicColors -> StageBackground.None
        coverSource && pref.background == StageBackground.Artist -> StageBackground.Dynamic
        else -> pref.background
    }
    val reduced = rememberReduceMotion()
    val context = LocalContext.current.applicationContext
    val uri by
        produceState(cover, cover, artist, style) {
            value = cover
            if (style == StageBackground.Artist && artist.isNotBlank()) {
                try {
                    val image =
                        withContext(Dispatchers.IO) {
                            com.music.spotui.di.Graph.api.lyricArtistBackdrop(
                                artist.substringBefore(",")
                            )
                        }
                    if (image.isNotBlank()) value = image
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {}
            }
        }
    val source = uri
    val blurRadius =
        if (style == StageBackground.Artist || style == StageBackground.Cover) pref.blur else 0
    val artwork by
        produceState<BackdropArt?>(null, source, style, blurRadius) {
            if (source.isBlank() || style == StageBackground.None) {
                value = null
                return@produceState
            }
            val dynamic = style == StageBackground.Dynamic || style == StageBackground.Color
            value =
                withContext(Dispatchers.IO) {
                    if (dynamic)
                        blurredCovers.get(source)?.let {
                            return@withContext it
                        }
                    val n = if (dynamic) Kawase.SIZE else 640
                    val loader = Glide.with(context)
                    val request =
                        loader
                            .asBitmap()
                            .load(app.myspoti.host.android.Covers.large(source))
                            .override(n, n)
                            .disallowHardwareConfig()
                            .submit()
                    try {
                        val original = runInterruptible { request.get() }
                        if (!dynamic)
                            return@withContext BackdropArt(
                                StackBlur.blur(original, blurRadius),
                                Color.Black,
                            )
                        val small = Bitmap.createScaledBitmap(original, n, n, true)
                        val pixels = IntArray(n * n)
                        small.getPixels(pixels, 0, n, 0, 0, n, n)
                        var red = 0
                        var green = 0
                        var blue = 0
                        for (color in pixels) {
                            red += color ushr 16 and 255
                            green += color ushr 8 and 255
                            blue += color and 255
                        }
                        val mean = Color(red / pixels.size, green / pixels.size, blue / pixels.size)
                        BackdropArt(
                                Bitmap.createBitmap(
                                    Kawase.blur(pixels),
                                    n,
                                    n,
                                    Bitmap.Config.ARGB_8888,
                                ),
                                mean,
                            )
                            .also { blurredCovers.put(source, it) }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        null
                    } finally {
                        loader.clear(request)
                    }
                }
        }
    val current = artwork
    val image = current?.bitmap
    val life by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsState()
    val visible = life.isAtLeast(Lifecycle.State.STARTED) && LocalWindowInfo.current.isWindowFocused
    Box(modifier.fillMaxSize().background(Color(0xff121212))) {
        if (style != StageBackground.None && image != null) {
            if (style == StageBackground.Color) {
                val avg = current.mean
                val high = if (pref[StageOption.RefinedColors]) .55f else .35f
                val deep = if (pref[StageOption.RefinedColors]) .3f else .6f
                Crossfade(
                    avg,
                    animationSpec = tween(if (reduced) 0 else 500),
                    label = "Cover palette",
                ) { c ->
                    Box(
                        Modifier.fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    listOf(
                                        Color(c.red * high, c.green * high, c.blue * high),
                                        Color(c.red * deep, c.green * deep, c.blue * deep),
                                    )
                                )
                            )
                    )
                }
            } else if (style == StageBackground.Dynamic) {
                var failed by remember { mutableStateOf(false) }
                if (failed)
                    Image(
                        image.asImageBitmap(),
                        null,
                        Modifier.fillMaxSize(),
                        contentScale = ContentScale.FillBounds,
                    )
                else {
                    var texture by remember { mutableStateOf<WarpTexture?>(null) }
                    AndroidView(
                        factory = { WarpTexture(it) { failed = true }.also { texture = it } },
                        modifier = Modifier.fillMaxSize(),
                        onRelease = { it.release() },
                        update = {},
                    )
                    var time by remember { mutableFloatStateOf(0f) }
                    var speed by remember { mutableFloatStateOf(if(playing) 1f else .1f) }
                    var previousImage by remember { mutableStateOf<Bitmap?>(null) }
                    var fadeStart by remember { mutableLongStateOf(0L) }
                    val motion = pref[StageOption.MotionBackground] && !reduced
                    val cap = if (pref[StageOption.LimitFrames]) pref.fps else 0
                    LaunchedEffect(texture, image, visible, motion, playing, cap) {
                        val surface = texture ?: return@LaunchedEffect
                        if (previousImage !== image) {
                            fadeStart =
                                if (previousImage == null || reduced) 0L
                                else android.os.SystemClock.elapsedRealtimeNanos()
                            previousImage = image
                        }
                        var last = 0L
                        do {
                            withFrameNanos { now ->
                                if (
                                    last != 0L &&
                                        cap > 0 &&
                                        now - last < 1_000_000_000L / cap - 500_000L
                                )
                                    return@withFrameNanos
                                if (last != 0L && visible && motion) {
                                    val target = if (playing) 1f else .1f
                                    speed += (target - speed) * .05f
                                    time += (now-last).coerceIn(0L,100_000_000L) / 1e9f * speed
                                }
                                last = now
                                val linear =
                                    if (fadeStart == 0L) 1f
                                    else
                                        ((android.os.SystemClock.elapsedRealtimeNanos() -
                                                fadeStart) / 500_000_000f)
                                            .coerceIn(0f, 1f)
                                if (linear >= 1f) fadeStart = 0L
                                val blend = ((1.0 - kotlin.math.cos(linear * Math.PI)) * .5).toFloat()
                                surface.display(image, time, blend)
                            }
                        } while (visible && (motion || fadeStart != 0L))
                    }
                }
            } else {
                Crossfade(
                    image,
                    animationSpec = tween(if (reduced) 0 else 500),
                    label = "Backdrop artwork",
                ) { art ->
                    Image(
                        art.asImageBitmap(),
                        null,
                        Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop,
                    )
                }
            }
        }
        Box(
            Modifier.fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = .12f), Color.Black.copy(alpha = .38f))
                    )
                )
        )
    }
}
