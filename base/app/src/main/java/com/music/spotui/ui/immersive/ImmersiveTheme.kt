package com.music.spotui.ui.immersive

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
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
    private val importedTheme get() = com.music.spotui.data.themes.ThemeManager.snapshot.active
    private val imported get() = com.music.spotui.data.themes.ThemeManager.snapshot.active?.colors
    private val effects get() = importedTheme?.effects
    private val artwork get() = if (AtmospherePref.dynamicColors && (adaptive || effects?.dynamicArtwork == true)) ArtworkAccent.color else null
    val Page: Color get() {
        val base = imported?.let { Color(it.background) } ?: if (gold) Color(0xFF050402) else Color.Black
        return artworkSurface(base, effects?.surfaceTint?.times(.45f) ?: 0f)
    }
    val Secondary: Color get() {
        val base = imported?.let { Color(it.surface) } ?: if (gold) Color(0xFF1C1A16) else Color(0xFF1C1C1E)
        return artworkSurface(base, effects?.surfaceTint ?: if (adaptive) .045f else 0f)
    }
    val Raised: Color get() {
        val base = imported?.let { Color(it.elevated) } ?: if (gold) Color(0xFF2C2921) else Color(0xFF2C2C2E)
        return artworkSurface(base, (effects?.surfaceTint ?: if (adaptive) .07f else 0f) * 1.25f)
    }
    private fun artworkSurface(base: Color, tint: Float) = artwork?.let { lerp(base, it, tint) } ?: base
    val Separator: Color get() = Text.copy(alpha = 0.10f)
    val Text: Color get() = imported?.let { Color(it.text) } ?: if (gold) Color(0xFFFFFAED) else Color(0xFFF5F5F7)
    val TextSecondary: Color get() = imported?.let { Color(it.secondary) } ?: if (gold) Color(0xFFC7BFAE) else Color(0xFFA1A1A6)
    val TextTertiary: Color get() = TextSecondary
    val Accent: Color get() = if (effects?.dynamicArtwork == true) artwork ?: imported?.let { Color(it.accent) } ?: CelestialThemePref.theme.accent
        else imported?.let { Color(it.accent) } ?: artwork ?: CelestialThemePref.theme.accent
    val OnAccent: Color get() = if (Accent.luminance() < .34f) Color.White else Color.Black
    val GlassFill: Color get() = Secondary.copy(alpha = effects?.glassOpacity ?: 0.78f)
    val GlassEdge: Color get() = lerp(Text, Accent, .45f).copy(alpha = if (effects?.presentation == com.music.spotui.data.themes.ThemePresentation.GLASSIFY) .26f else .16f)
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
