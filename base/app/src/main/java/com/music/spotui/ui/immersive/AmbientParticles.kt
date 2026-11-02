package com.music.spotui.ui.immersive

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.music.spotui.data.preferences.AtmospherePref
import com.music.spotui.ui.look.rememberReduceMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.sin

/** Draw-only atmosphere; no pointer input, layout change, or per-frame allocations. */
@Composable
fun AmbientParticles(color: Color, lyricsMode: Boolean = false, modifier: Modifier = Modifier, moving: Boolean = true) {
    val energy = app.myspoti.power.EnergySettings.state.collectAsStateWithLifecycle().value
    val enabled = AtmospherePref.particles && energy.policy.allowCanvas
    val intensity = AtmospherePref.intensity
    val reduceMotion = rememberReduceMotion()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val tick = remember { mutableLongStateOf(0L) }
    val points = remember {
        List(30) { i -> Offset((i * 0.6180339f + 0.13f) % 1f, (i * 0.381966f + 0.29f) % 1f) }
    }
    LaunchedEffect(enabled, reduceMotion, lifecycle, moving) {
        if (!enabled || reduceMotion || !moving) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (isActive) {
                tick.longValue = System.nanoTime()
                delay(50L)
            }
        }
    }
    if (!enabled) return
    Canvas(modifier.fillMaxSize()) {
        val time = if (reduceMotion) 0.0 else tick.longValue / 1_000_000_000.0
        val count = when (intensity) { 0 -> 10; 2 -> 30; else -> 18 }
        val base = if (lyricsMode) 0.32f else 0.46f
        for (i in 0 until count) {
            val point = points[i]
            val phase = time * (0.12 + i % 4 * 0.025) + i * 2.41
            val x = (point.x + if (reduceMotion) 0f else (sin(phase) * 0.007).toFloat()) * size.width
            val y = (point.y + if (reduceMotion) 0f else (sin(phase * 0.73) * 0.009).toFloat()) * size.height
            val fade = (0.55 + 0.35 * sin(phase + PI / 2)).toFloat()
            val alpha = base * fade * if (i % 7 == 0) 0.8f else 0.48f
            val center = Offset(x, y)
            val radius = if (i % 7 == 0) 1.5.dp.toPx() else 0.7.dp.toPx()
            drawCircle(color.copy(alpha = alpha), radius, center)
            if (i % 7 == 0 && fade > 0.74f) {
                val ray = radius * 3.2f
                drawLine(color.copy(alpha = alpha * 0.45f), Offset(x - ray, y), Offset(x + ray, y), 0.6.dp.toPx(), StrokeCap.Round)
                drawLine(color.copy(alpha = alpha * 0.45f), Offset(x, y - ray), Offset(x, y + ray), 0.6.dp.toPx(), StrokeCap.Round)
            }
        }
    }
}
