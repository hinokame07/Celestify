package com.music.spotui.ui.immersive.lyrics

import android.graphics.Bitmap
import android.view.TextureView
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay

internal data class CinemaLight(val upper: Color, val middle: Color, val lower: Color) {
    companion object {
        fun from(frame: Bitmap): CinemaLight? {
            fun band(start: Int, end: Int): Color? {
                var r = 0
                var g = 0
                var b = 0
                var count = 0
                for (y in start until end) for (x in 0 until frame.width) {
                    val c = frame.getPixel(x, y)
                    if (c ushr 24 == 0) continue
                    r += c ushr 16 and 255
                    g += c ushr 8 and 255
                    b += c and 255
                    count++
                }
                if (count == 0) return null
                val scale = .79f / (255f * count)
                return Color(r * scale, g * scale, b * scale)
            }
            val a = frame.height / 3
            val b = frame.height * 2 / 3
            return CinemaLight(
                band(0, a) ?: return null,
                band(a, b) ?: return null,
                band(b, frame.height) ?: return null,
            )
        }
    }
}

/** Read the texture that is already presenting the clip. No network request or second decoder. */
@Composable
internal fun videoLight(texture: TextureView?, playing: Boolean, reduced: Boolean): CinemaLight? {
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsState()
    val visible =
        LocalWindowInfo.current.isWindowFocused && lifecycle.isAtLeast(Lifecycle.State.STARTED)
    var palette by remember(texture) { mutableStateOf<CinemaLight?>(null) }
    LaunchedEffect(texture, visible, playing, reduced) {
        if (texture == null || !visible) return@LaunchedEffect
        val sample = Bitmap.createBitmap(12, 12, Bitmap.Config.ARGB_8888)
        var last = -1L
        while (true) {
            val timestamp = runCatching { texture.surfaceTexture?.timestamp }.getOrNull() ?: 0L
            if (texture.isAvailable && timestamp > 0 && timestamp != last) {
                val next =
                    runCatching { texture.getBitmap(sample)?.let(CinemaLight::from) }.getOrNull()
                if (next != null) {
                    palette = next
                    last = timestamp
                }
            }
            delay(if (reduced || !playing) 1000L else 350L)
        }
    }
    return palette
}

@Composable
internal fun CinemaVideoBackground(light: CinemaLight, reduced: Boolean) {
    val duration = if (reduced) 0 else 520
    val upper by animateColorAsState(light.upper, tween(duration), label = "Video highlights")
    val mid by animateColorAsState(light.middle, tween(duration), label = "Video midtones")
    val lower by animateColorAsState(light.lower, tween(duration), label = "Video shadows")
    Canvas(Modifier.fillMaxSize()) {
        drawRect(
            Brush.linearGradient(
                listOf(upper, mid, lower),
                Offset.Zero,
                Offset(size.width * .72f, size.height),
            )
        )
        drawRect(
            Brush.verticalGradient(
                listOf(Color.Black.copy(alpha = .12f), Color.Black.copy(alpha = .42f))
            )
        )
    }
}
