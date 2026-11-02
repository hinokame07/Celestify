package com.music.spotui.ui.immersive

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.music.spotui.ui.look.ImmersiveDisplay
import com.music.spotui.ui.look.ImmersiveSans
import com.music.spotui.data.preferences.AppearancePref
import com.music.spotui.data.preferences.CelestialTheme
import com.music.spotui.data.preferences.CelestialThemePref
import com.music.spotui.data.preferences.AtmospherePref

/*
 * The Immersive look's tokens, shared by every Immersive screen so they read as one app:
 * pearl and ivory pages, Inter, editorial titles, rounded covers, restrained glass
 * and an accent taken from artwork on content where one is available.
 */
object Immersive {
    // Colours.
    private val gold: Boolean get() = CelestialThemePref.theme == CelestialTheme.GOLD
    private val adaptive get() = CelestialThemePref.theme == CelestialTheme.ADAPTIVE
    private val artwork get() = if (adaptive && AtmospherePref.dynamicColors) ArtworkAccent.color else null
    private val imported get() = com.music.spotui.data.themes.ThemeManager.snapshot.active?.colors
    val Page: Color get() = imported?.let { Color(it.background) } ?: if (gold) Color(0xFF080706) else Color(0xFF050507)
    val Secondary: Color get() = imported?.let { Color(it.surface) } ?: if (gold) Color(0xFF1B1814) else if (adaptive) artworkSurface(Color(0xFF141414), 0.05f) else Color(0xFF0D1016)
    val Raised: Color get() = imported?.let { Color(it.elevated) } ?: if (gold) Color(0xFF252119) else if (adaptive) artworkSurface(Color(0xFF222222), 0.08f) else Color(0xFF171B24)
    private fun artworkSurface(base: Color, tint: Float) = artwork?.let { lerp(base, it, tint) } ?: base
    val Separator: Color get() = Text.copy(alpha = 0.10f)
    val Text: Color get() = imported?.let { Color(it.text) } ?: if (gold) Color(0xFFFFF9ED) else if (adaptive) Color(0xFFF5F5F5) else Color(0xFFF7F9FF)
    val TextSecondary: Color get() = imported?.let { Color(it.secondary) } ?: if (gold) Color(0xFFC6BAA7) else if (adaptive) Color(0xFFB3B3B3) else Color(0xFFA8B2C3)
    val TextTertiary: Color get() = TextSecondary
    val Accent: Color get() = imported?.let { Color(it.accent) } ?: artwork ?: CelestialThemePref.theme.accent
    val OnAccent: Color get() = Color(0xFF090B10)
    val GlassFill: Color get() = Secondary.copy(alpha = 0.84f)
    val GlassEdge: Color get() = Accent.copy(alpha = 0.18f)
    /** The red of a destructive swipe, menu entry or confirmation (Leave, Remove, an error). */
    val Destructive = Color(0xFFFF453A)

    // The player keeps enough slate contrast over pearl and champagne artwork light.
    val OnArtwork: Color get() = Text
    val OnArtworkSecondary: Color get() = TextSecondary

    // Shapes.
    val CoverSmall: Shape = RoundedCornerShape(8.dp)
    val CoverMedium: Shape = RoundedCornerShape(12.dp)
    val CoverLarge: Shape = RoundedCornerShape(18.dp)
    val Card: Shape = RoundedCornerShape(22.dp)
    val Button: Shape = RoundedCornerShape(16.dp)

    // Type (Inter).
    private val base get() = TextStyle(fontFamily = ImmersiveSans, color = Text)
    private val display get() = TextStyle(fontFamily = ImmersiveDisplay, color = Text)
    val LargeTitle get() = display.copy(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.9).sp)
    val Title get() = display.copy(fontSize = 23.sp, lineHeight = 29.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.55).sp)
    val Headline get() = display.copy(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.2).sp)
    val Body get() = base.copy(fontSize = 16.sp, lineHeight = 22.sp)
    val BodyStrong get() = Body.copy(fontWeight = FontWeight.SemiBold)
    val Subhead get() = base.copy(fontSize = 14.sp, lineHeight = 20.sp, color = TextSecondary)
    val Caption get() = base.copy(fontSize = 13.sp, lineHeight = 18.sp, color = TextSecondary)
    val Lyric get() = display.copy(fontSize = 30.sp, lineHeight = 37.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.45).sp)
    val ArtworkTitle get() = Title.copy(color = OnArtwork)
    val ArtworkHeadline get() = Headline.copy(color = OnArtwork)
    val ArtworkBody get() = Body.copy(color = OnArtwork)
    val ArtworkBodyStrong get() = BodyStrong.copy(color = OnArtwork)
    val ArtworkSubhead get() = Subhead.copy(color = OnArtworkSecondary)
    val ArtworkCaption get() = Caption.copy(color = OnArtworkSecondary)
    val ArtworkLyric get() = Lyric.copy(color = OnArtwork)

    // Spacing.
    val Gutter = 20.dp
    val RowHeight = 60.dp
    /** Room the floating tab bar and mini player take at the bottom of every page. */
    val BottomChrome = 170.dp
}

/** A translucent bar or capsule (tab bar, mini player, menus). */
fun Modifier.glass(shape: Shape = CircleShape): Modifier =
    this.background(Immersive.GlassFill, shape).border(1.dp, Immersive.GlassEdge, shape)
