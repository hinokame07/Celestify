package com.music.spotui.ui.immersive.lyrics

import android.app.PictureInPictureParams
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.music.spotui.ui.immersive.Immersive
import com.music.spotui.ui.theme.SpotuiTheme

/** A separate task lets Android keep lyrics visible while the listener uses another app. */
class FloatingLyricsActivity : ComponentActivity() {
    private var floating by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        floating = isInPictureInPictureMode
        setContent {
            SpotuiTheme {
                CompositionLocalProvider(LocalFloatingLyrics provides floating) {
                    ImmersiveLyricsPanel(
                        Modifier.fillMaxSize().background(Immersive.Page),
                        PaddingValues(horizontal = 8.dp),
                    )
                }
            }
        }
    }

    private var entered = false

    override fun onPostResume() {
        super.onPostResume()
        if (!entered && !isInPictureInPictureMode) {
            entered = true
            window.decorView.post {
                if (!isFinishing && !isDestroyed)
                    runCatching {
                        enterPictureInPictureMode(
                            PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 10))
                                .build()
                        )
                    }
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        inPip: Boolean,
        config: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(inPip, config)
        floating = inPip
        entered = true
    }
}

internal val LocalFloatingLyrics = compositionLocalOf { false }
