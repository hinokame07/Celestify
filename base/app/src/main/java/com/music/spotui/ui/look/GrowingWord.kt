// SPDX-License-Identifier: AGPL-3.0-only
// Adapted for Android/Compose from Spikerko/spicy-lyrics, LyricsAnimator.ts,
// commit 34ad8c683204c522f227060475bf4f8aae36508e. See THIRD_PARTY_NOTICES.md.
package com.music.spotui.ui.look

import androidx.compose.animation.core.CubicBezierEasing
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

/** The refreshed Spicy Lyrics letter wave, sampled directly from the audio clock. */
class GrowingWord internal constructor(val index: Int, word: SweptWord, last: Boolean) {
    val startMs = word.startMs
    val endMs = word.endMs
    private val count = word.text.length
    private val held = (endMs - startMs).coerceAtLeast(1000L).toFloat()
    private val duration = held * if (last) 1.2f else 1f
    private val amount = (strength(held / 2000f) * 0.6f * if (last) 1.6f else 1f).coerceAtMost(1.2f)
    private val blur = (strength(held / 3000f) * 0.5f * if (last) 1.5f else 1f).coerceAtMost(0.8f)
    private val stagger = duration * 0.4f / count
    val restsAtMs = startMs + (stagger * (count - 1) + maxOf(duration, duration * 1.4f - 400f)).toLong() + 1

    fun sampleInto(charIndex: Int, positionMs: Long, into: CharGrowth) {
        val at = positionMs - startMs - stagger * charIndex
        val phase = (at / duration).coerceIn(0f, 1f)
        val swell = if (phase < 0.5f) attack.transform(phase * 2f)
            else 1f - release.transform((phase - 0.5f) * 2f)
        val floatPhase = ((at + 400f) / (duration * 1.4f)).coerceIn(0f, 1f)
        into.scale = 1f + swell * 0.1f * amount
        into.shift = -swell * 0.03f * amount * (count / 2f - charIndex)
        // The native renderer expresses lift in units of its existing 2dp rise.
        into.rise = (swell * 0.025f * amount + sin(floatPhase * PI).toFloat() * 0.05f) * 16f
        into.bloom = swell * blur
    }

    private companion object {
        val attack = CubicBezierEasing(0.2f, 0.4f, 0.58f, 1f)
        val release = CubicBezierEasing(0.3f, 0f, 0.58f, 1f)
        fun strength(x: Float): Float = if (x > 1f) sqrt(x) else x * x * x
    }
}
