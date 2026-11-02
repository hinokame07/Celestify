package com.music.spotui.data.preferences

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import com.music.spotui.di.Graph

enum class CelestialTheme(val label: String, val accent: Color) {
    BLUE("Celestial Midnight", Color(0xFFB9DEFF)),
    GOLD("Golden Seraph", Color(0xFFE9D5A8)),
    ADAPTIVE("Adaptive Celestial", Color(0xFFE6E6E6));
}

/** Public Celestify palette, independent of the app's stable technical identifiers. */
object CelestialThemePref {
    private const val PREFS = "celestify_appearance"
    private const val KEY = "theme"
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var theme by mutableStateOf(
        CelestialTheme.entries.firstOrNull { it.name == prefs(Graph.app).getString(KEY, null) }
            ?: CelestialTheme.ADAPTIVE,
    )
        private set

    fun set(context: Context, value: CelestialTheme) {
        theme = value
        prefs(context).edit().putString(KEY, value.name).apply()
    }
}
