package com.music.spotui.ui.immersive.shell

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import com.music.spotui.ui.immersive.Immersive

/** Material fills share the existing recorded-backdrop renderer and its API 29/30 fallback. */
enum class DarkCrystal {
    OBSIDIAN, MOONLIGHT, SERAPH, OVERLAY;
    val fill: Color get() = when (this) {
        OBSIDIAN -> Immersive.GlassFill
        MOONLIGHT -> lerp(Immersive.GlassFill, Immersive.Accent, .06f)
        SERAPH -> lerp(Immersive.GlassFill, Color(0xFFFFD60A), .05f)
        OVERLAY -> Immersive.Raised.copy(alpha = .90f)
    }
}
