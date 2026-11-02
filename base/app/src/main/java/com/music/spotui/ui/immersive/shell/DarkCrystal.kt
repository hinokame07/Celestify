package com.music.spotui.ui.immersive.shell

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import com.music.spotui.ui.immersive.Immersive

/** Material fills share the existing recorded-backdrop renderer and its API 29/30 fallback. */
enum class DarkCrystal {
    OBSIDIAN, MOONLIGHT, SERAPH, OVERLAY;
    val fill: Color get() = when (this) {
        OBSIDIAN -> Immersive.Secondary.copy(alpha = .70f)
        MOONLIGHT -> lerp(Immersive.Secondary, Immersive.Accent, .06f).copy(alpha = .72f)
        SERAPH -> lerp(Immersive.Secondary, Color(0xFFE9D5A8), .05f).copy(alpha = .76f)
        OVERLAY -> Immersive.Raised.copy(alpha = .92f)
    }
}
