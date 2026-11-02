package com.music.spotui.ui.immersive

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import com.music.spotui.di.Graph
import com.music.spotui.di.Palette


/** A small, cached artwork accent for controls outside the full player. */
internal object ArtworkAccent {
    var color by mutableStateOf<Color?>(null)
        private set

    fun update(value: Color?) { color = value?.let(::readableArtworkAccent) }
}

/** Keep the cover's own hue, lifting only enough for text and controls on dark glass. */
internal fun readableArtworkAccent(seed: Color): Color {
    val ink = if (seed.luminance() > 0.84f) lerp(seed, Color.Black, 0.08f) else seed
    if (ink.luminance() >= 0.48f) return ink
    var low = 0f
    var high = 1f
    repeat(9) {
        val amount = (low + high) / 2f
        if (lerp(ink, Color.White, amount).luminance() < 0.48f) low = amount else high = amount
    }
    return lerp(ink, Color.White, high)
}

/** Load only on track changes; the palette cache makes returning to a song immediate. */
@Composable
internal fun BindArtworkAccent() {
    val cover = Graph.currentSongState.coverUri.value
    LaunchedEffect(cover) {
        ArtworkAccent.update(cover.takeIf { it.isNotBlank() }?.let { Palette.cachedFirst(it) })
        if (cover.isNotBlank()) {
            Palette().extractFirstColorFromImageUrl(Graph.app, cover) { color ->
                if (Graph.currentSongState.coverUri.value == cover) ArtworkAccent.update(color)
            }
        }
    }
}
