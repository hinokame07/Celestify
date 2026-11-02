package com.music.spotui.data.preferences

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.music.spotui.di.Graph

/** Visual options for the Immersive look. All defaults favor a quiet, low-cost atmosphere. */
object AtmospherePref {
    private const val FILE = "settings_prefs"
    private val initial = Graph.app.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    var particles by mutableStateOf(initial.getBoolean("ambient_particles", true))
        private set
    var intensity by mutableIntStateOf(initial.getInt("particle_intensity", 1).coerceIn(0, 2))
        private set
    var dynamicColors by mutableStateOf(initial.getBoolean("dynamic_artwork_colors", true))
        private set
    var lyricsGlow by mutableStateOf(initial.getBoolean("lyrics_glow", true))
        private set
    var reduceAnimations by mutableStateOf(initial.getBoolean("reduce_animations", false))
        private set
    var lyricsOffsetMs by mutableIntStateOf(initial.getInt("lyrics_offset_ms", 0).coerceIn(-2000, 2000))
        private set

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun setParticles(context: Context, value: Boolean) { particles = value; prefs(context).edit().putBoolean("ambient_particles", value).apply() }
    fun setIntensity(context: Context, value: Int) { intensity = value.coerceIn(0, 2); prefs(context).edit().putInt("particle_intensity", intensity).apply() }
    fun setDynamicColors(context: Context, value: Boolean) { dynamicColors = value; prefs(context).edit().putBoolean("dynamic_artwork_colors", value).apply() }
    fun setLyricsGlow(context: Context, value: Boolean) { lyricsGlow = value; prefs(context).edit().putBoolean("lyrics_glow", value).apply() }
    fun setReduceAnimations(context: Context, value: Boolean) { reduceAnimations = value; prefs(context).edit().putBoolean("reduce_animations", value).apply() }
    fun setLyricsOffset(context: Context, value: Int) { lyricsOffsetMs = value.coerceIn(-2000, 2000); prefs(context).edit().putInt("lyrics_offset_ms", lyricsOffsetMs).apply() }
}
