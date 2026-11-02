package com.music.spotui.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp

val AppBackground: Color get() = com.music.spotui.ui.immersive.Immersive.Page
val GridBackground: Color get() = com.music.spotui.ui.immersive.Immersive.Secondary
/** The selected look's accent, shared with onboarding and legacy Material controls. */
val AppPalette: Color get() = AppAccent
val AppAccent: Color get() = com.music.spotui.ui.immersive.Immersive.Accent

/** Primary text and icons. */
val AppText: Color get() = com.music.spotui.ui.immersive.Immersive.Text
/** Secondary text and icons. */
val AppMuted: Color get() = com.music.spotui.ui.immersive.Immersive.TextSecondary
/** Destructive actions (delete, leave, block) and failures shown as text. */
val AppDestructive = Color(0xFFFF453A)
/** What a tint is mixed with to make a header. */
val AppShade: Color = Color.Black

/** One of the palette's raised greys (#181818 ... #3E3E3E): "a bit raised from the page". */
fun tone(argb: Long): Color = when (argb) {
    0xFF282828L -> com.music.spotui.ui.immersive.Immersive.Raised
    0xFF181818L -> com.music.spotui.ui.immersive.Immersive.Secondary
    else -> Color(argb)
}

/** The cover's colour as a page header: darkened toward black, so the title stays readable. */
fun headerTint(tint: Color, amount: Float): Color = lerp(tint, Color.Black, amount)
