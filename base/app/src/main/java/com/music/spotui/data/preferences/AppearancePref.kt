package com.music.spotui.data.preferences

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** The page palette. A saved light choice redraws all Compose readers immediately. */
object AppearancePref {
    private const val PREF = "settings_prefs"
    private const val KEY = "light_appearance"

    var light by mutableStateOf(
        com.music.spotui.di.Graph.app.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .getBoolean(KEY, true),
    )
        private set

    /** Celestify's two public palettes are light, including for migrated installations. */
    val activeLight: Boolean get() = false

    fun setLight(context: Context, enabled: Boolean) {
        light = enabled
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, enabled).apply()
    }
}
