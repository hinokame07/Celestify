package com.music.spotui.ui.theme

import android.app.Activity
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

/** Shared palette for Material controls that appear inside both presentation paths. */
private fun premiumDarkColorScheme(accent: Color) = darkColorScheme(
    primary = accent,
    onPrimary = Color.Black,
    primaryContainer = lerp(com.music.spotui.ui.immersive.Immersive.Secondary, accent, .12f),
    onPrimaryContainer = accent,
    secondary = AppText,
    onSecondary = Color.Black,
    secondaryContainer = com.music.spotui.ui.immersive.Immersive.Secondary,
    onSecondaryContainer = AppText,
    tertiary = accent,
    onTertiary = Color.Black,
    background = AppBackground,
    onBackground = AppText,
    surface = AppBackground,
    onSurface = AppText,
    surfaceVariant = com.music.spotui.ui.immersive.Immersive.Secondary,
    onSurfaceVariant = AppMuted,
    surfaceTint = Color.Transparent,
    surfaceDim = AppBackground,
    surfaceBright = Color(0xFF303038),
    surfaceContainerLowest = AppBackground,
    surfaceContainerLow = com.music.spotui.ui.immersive.Immersive.Secondary,
    surfaceContainer = com.music.spotui.ui.immersive.Immersive.Raised,
    surfaceContainerHigh = com.music.spotui.ui.immersive.Immersive.Raised,
    surfaceContainerHighest = com.music.spotui.ui.immersive.Immersive.Raised,
    inverseSurface = Color.White,
    inverseOnSurface = Color.Black,
    inversePrimary = accent,
    outline = Color(0xFF777781),
    outlineVariant = Color(0xFF3A3A42),
    error = Color(0xFFF3727F),
    onError = Color.Black,
    scrim = Color.Black,
)

private fun premiumLightColorScheme(accent: Color) = lightColorScheme(
    primary = accent,
    onPrimary = Color.White,
    primaryContainer = lerp(Color.White, accent, 0.16f),
    onPrimaryContainer = lerp(accent, Color.Black, 0.22f),
    secondary = Color(0xFF60606B),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE8E8EE),
    onSecondaryContainer = Color(0xFF17171C),
    tertiary = accent,
    onTertiary = Color.White,
    tertiaryContainer = lerp(Color.White, accent, 0.16f),
    onTertiaryContainer = lerp(accent, Color.Black, 0.22f),
    background = AppBackground,
    onBackground = AppText,
    surface = AppBackground,
    onSurface = AppText,
    surfaceVariant = com.music.spotui.ui.immersive.Immersive.Secondary,
    onSurfaceVariant = AppMuted,
    surfaceTint = Color.Transparent,
    surfaceDim = Color(0xFFE8E8EE),
    surfaceBright = Color.White,
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = com.music.spotui.ui.immersive.Immersive.Secondary,
    surfaceContainer = com.music.spotui.ui.immersive.Immersive.Raised,
    surfaceContainerHigh = com.music.spotui.ui.immersive.Immersive.Secondary,
    surfaceContainerHighest = com.music.spotui.ui.immersive.Immersive.Secondary,
    inverseSurface = Color(0xFF24242C),
    inverseOnSurface = Color(0xFFF7F7FA),
    inversePrimary = lerp(accent, Color.White, 0.3f),
    outline = Color(0xFF777781),
    outlineVariant = Color(0xFFD1D1D9),
    error = Color(0xFFB32635),
    onError = Color.White,
    scrim = Color.Black,
)

@Composable
fun SpotuiTheme(
    content: @Composable () -> Unit
) {
    val energy by app.myspoti.power.EnergySettings.state.collectAsStateWithLifecycle()
    val policy = energy.policy
    androidx.compose.runtime.LaunchedEffect(policy.videoMaxHeight, policy.allowBackgroundLookups) {
        com.music.spotui.video.MusicVideoController.onEnergyPolicyChanged()
    }
    val immersive = com.music.spotui.data.preferences.LookPref.look == com.music.spotui.data.preferences.Look.IMMERSIVE
    androidx.compose.runtime.LaunchedEffect(Unit) { com.music.spotui.data.themes.ThemeManager.load() }
    if (com.music.spotui.data.preferences.AtmospherePref.dynamicColors &&
        com.music.spotui.data.preferences.CelestialThemePref.theme == com.music.spotui.data.preferences.CelestialTheme.ADAPTIVE) {
        com.music.spotui.ui.immersive.BindArtworkAccent()
    }
    val light = com.music.spotui.data.preferences.AppearancePref.activeLight
    val lightSystemBars = light
    val accent = AppAccent
    val visualScheme: ColorScheme = if (light) premiumLightColorScheme(accent) else premiumDarkColorScheme(accent)
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.attributes = window.attributes.apply { preferredRefreshRate = policy.displayRefreshCap }
            window.statusBarColor = Color.Transparent.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = lightSystemBars
            // Keep the navigation surface transparent under the page and modal sheets.
            window.navigationBarColor = Color.Transparent.toArgb()
            // Without this Android lays its own translucent scrim on a transparent bar (API 29+),
            // which showed as a differently coloured strip under the full-screen Canvas.
            window.isNavigationBarContrastEnforced = false
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = lightSystemBars
            // Behind the first frame and under overscroll: the palette's page colour.
            window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(AppBackground.toArgb()))
        }
    }

    MaterialTheme(
        colorScheme = visualScheme,
        typography = if (immersive) ImmersiveTypography else Typography,
    ) {
        // Bare Text() does not inherit MaterialTheme.typography automatically.
        androidx.compose.material3.ProvideTextStyle(
            value = androidx.compose.material3.LocalTextStyle.current.copy(
                fontFamily = if (immersive) com.music.spotui.ui.look.ImmersiveSans else AppSans,
                letterSpacing = (-0.2).sp,
            ),
            content = content,
        )
    }
}
