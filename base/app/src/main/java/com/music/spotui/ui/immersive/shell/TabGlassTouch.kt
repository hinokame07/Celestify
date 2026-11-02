package com.music.spotui.ui.immersive.shell

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp

/**
 * Optical feedback follows the original pointer through the hand-off from a tab click to a drag.
 * Observe without consuming events: tab navigation, scrolling and accessibility keep ownership.
 */
internal fun Modifier.tabGlassTouch(
    source: MutableInteractionSource,
    reduceMotion: Boolean,
): Modifier = composed {
    var contact by remember { mutableStateOf(Offset.Zero) }
    var down by remember { mutableStateOf(false) }
    val strength by
        animateFloatAsState(
            if (down) 1f else 0f,
            animationSpec = if (reduceMotion) snap() else tween(if (down) 80 else 190),
            label = "Tab glass contact",
        )
    this.pointerInput(source) {
            awaitEachGesture {
                val first =
                    awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                val press = PressInteraction.Press(first.position)
                var released = false
                contact = first.position
                down = true
                source.tryEmit(press)
                try {
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val pointer = event.changes.firstOrNull { it.id == first.id } ?: break
                        contact =
                            Offset(
                                pointer.position.x.coerceIn(0f, size.width.toFloat()),
                                pointer.position.y.coerceIn(0f, size.height.toFloat()),
                            )
                        if (!pointer.pressed) {
                            released = true
                            break
                        }
                    } while (true)
                } finally {
                    down = false
                    source.tryEmit(
                        if (released) PressInteraction.Release(press)
                        else PressInteraction.Cancel(press)
                    )
                }
            }
        }
        .drawWithContent {
            drawContent()
            if (strength <= 0f || size.minDimension <= 0f) return@drawWithContent
            val corner = CornerRadius(size.height / 2)
            val shine =
                Brush.radialGradient(
                    colors =
                        listOf(
                            Color.White.copy(alpha = .16f * strength),
                            Color.White.copy(alpha = .05f * strength),
                            Color.Transparent,
                        ),
                    center = contact,
                    radius = size.height * 1.65f,
                )
            drawRoundRect(shine, cornerRadius = corner)
            val rim =
                Brush.radialGradient(
                    colors =
                        listOf(
                            Color.White.copy(alpha = .59f * strength),
                            Color.White.copy(alpha = .08f * strength),
                        ),
                    center = contact,
                    radius = size.height * 2.4f,
                )
            drawRoundRect(rim, cornerRadius = corner, style = Stroke(1.3.dp.toPx()))
        }
}
