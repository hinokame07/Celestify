package com.music.spotui.ui.immersive.lyrics

import android.graphics.Bitmap
import android.view.TextureView
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay

/** Two columns of three samples preserve colors that would cancel in a row average. */
internal data class CinemaLight(val patches: List<Color>) {
    val upper
        get() = patches[0]

    val middle
        get() = patches[2]

    val lower
        get() = patches[4]

    companion object {
        fun from(frame: Bitmap): CinemaLight? {
            if (frame.width < 2 || frame.height < 3) return null
            val pixels = IntArray(frame.width * frame.height)
            frame.getPixels(pixels, 0, frame.width, 0, 0, frame.width, frame.height)
            val patches = ArrayList<Color>(6)
            for (row in 0..2) for (col in 0..1) {
                // Pick a representative local color. Weight chroma so a vivid costume or light
                // survives the darker scenery, while an achromatic shot stays achromatic.
                val bins = IntArray(64)
                var red = 0
                var green = 0
                var blue = 0
                var weight = 0
                fun bin(r: Int, g: Int, b: Int) =
                    ((r ushr 6) shl 4) or ((g ushr 6) shl 2) or (b ushr 6)
                val ys = row * frame.height / 3 until (row + 1) * frame.height / 3
                val xs = col * frame.width / 2 until (col + 1) * frame.width / 2
                for (y in ys) for (x in xs) {
                    val pixel = pixels[y * frame.width + x]
                    if (pixel ushr 24 == 0) continue
                    val r = pixel ushr 16 and 255
                    val g = pixel ushr 8 and 255
                    val b = pixel and 255
                    val w = 32 + maxOf(r, g, b) - minOf(r, g, b)
                    bins[bin(r, g, b)] += w
                    red += r * w
                    green += g * w
                    blue += b * w
                    weight += w
                }
                if (weight == 0) return null
                val dominant = bins.indices.maxBy { bins[it] }
                var rr = 0
                var gg = 0
                var bb = 0
                var count = 0
                for (y in ys) for (x in xs) {
                    val pixel = pixels[y * frame.width + x]
                    val r = pixel ushr 16 and 255
                    val g = pixel ushr 8 and 255
                    val b = pixel and 255
                    if (pixel ushr 24 != 0 && bin(r, g, b) == dominant) {
                        rr += r
                        gg += g
                        bb += b
                        count++
                    }
                }
                fun channel(sum: Int, local: Int) =
                    (.34f * sum / weight + .66f * local / count) / 255f
                patches += Color(channel(red, rr), channel(green, gg), channel(blue, bb))
            }
            return CinemaLight(patches)
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
        val sample = Bitmap.createBitmap(24, 18, Bitmap.Config.ARGB_8888)
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
internal fun CinemaVideoBackground(
    light: CinemaLight,
    reduced: Boolean,
    playing: Boolean,
    overlay: Boolean = false,
) {
    val visible by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsState()
    val moving =
        playing &&
            !reduced &&
            LocalWindowInfo.current.isWindowFocused &&
            visible.isAtLeast(Lifecycle.State.STARTED)
    val phase = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(moving) {
        if (!moving) return@LaunchedEffect
        var last = 0L
        while (true) withFrameNanos { now ->
            if (last == 0L) last = now
            if (now - last >= 32_000_000L) {
                phase.floatValue += (now - last).coerceAtMost(100_000_000L) / 1e9f * .15f
                last = now
            }
        }
    }
    val colors =
        light.patches.mapIndexed { index, color ->
            animateColorAsState(
                color,
                tween(if (reduced) 0 else 690),
                label = "Cinema light " + index,
            )
        }
    androidx.compose.foundation.layout.Box(
        Modifier.fillMaxSize().drawWithCache {
            val fields =
                colors.map { state ->
                    val c = state.value
                    Brush.radialGradient(
                        colorStops =
                            arrayOf(
                                0f to c.copy(alpha = if (overlay) .52f else .91f),
                                .45f to c.copy(alpha = if (overlay) .29f else .57f),
                                1f to c.copy(alpha = 0f),
                            ),
                        center = Offset.Zero,
                        radius = 1f,
                    )
                }
            val shade =
                Brush.verticalGradient(
                    listOf(Color.Black.copy(alpha = .14f), Color.Black.copy(alpha = .39f))
                )
            onDrawBehind {
                if (!overlay) drawRect(Color(0xff101018))
                val t = phase.floatValue
                for (i in fields.indices) {
                    val x =
                        ((if (i % 2 == 0) .17f else .83f) + .16f * kotlin.math.sin(t + i * 1.63f)) *
                            size.width
                    val y =
                        ((i / 2 + .5f) / 3f + .14f * kotlin.math.cos(t * .84f + i * 1.18f)) *
                            size.height
                    withTransform({
                        translate(x, y)
                        scale(
                            size.width * (.61f + .07f * kotlin.math.cos(t + i)),
                            size.height * .58f,
                            Offset.Zero,
                        )
                    }) {
                        drawCircle(fields[i], radius = 1f, center = Offset.Zero)
                    }
                }
                if (!overlay) drawRect(shade)
            }
        }
    )
}
