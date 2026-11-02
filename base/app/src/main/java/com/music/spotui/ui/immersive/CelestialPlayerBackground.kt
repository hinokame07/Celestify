package com.music.spotui.ui.immersive

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import com.music.spotui.data.preferences.AtmospherePref
import com.music.spotui.ui.look.MeshPalette

/** Pale artwork light, drawn without a full-screen blur pass. Track changes crossfade. */
@Composable
fun CelestialPlayerBackground(palette: MeshPalette, modifier: Modifier = Modifier) {
    val base = Immersive.Page
    val mist = Immersive.Secondary
    val colors = if (AtmospherePref.dynamicColors) palette.colors else emptyList()
    val artwork = colors.firstOrNull() ?: mist
    val artworkSecond = colors.getOrNull(1) ?: mist
    val spec = if (com.music.spotui.ui.look.rememberReduceMotion()) androidx.compose.animation.core.snap<Color>() else tween<Color>(1_200)
    val upper by animateColorAsState(lerp(mist, artwork, 0.36f), spec, label = "celestialUpper")
    val lower by animateColorAsState(lerp(base, artworkSecond, 0.26f), spec, label = "celestialLower")
    Canvas(modifier.fillMaxSize()) {
        drawRect(brush = Brush.verticalGradient(listOf(base, mist, base)))
        val upperCenter = Offset(size.width * 0.47f, size.height * 0.20f)
        val upperRadius = size.maxDimension * 0.75f
        drawCircle(brush = Brush.radialGradient(
            colors = listOf(upper.copy(alpha = 0.90f), upper.copy(alpha = 0f)),
            center = upperCenter, radius = upperRadius,
        ), center = upperCenter, radius = upperRadius)
        val lowerCenter = Offset(size.width * 0.84f, size.height * 0.80f)
        val lowerRadius = size.maxDimension * 0.55f
        drawCircle(brush = Brush.radialGradient(
            colors = listOf(lower.copy(alpha = 0.85f), lower.copy(alpha = 0f)),
            center = lowerCenter, radius = lowerRadius,
        ), center = lowerCenter, radius = lowerRadius)
    }
}
