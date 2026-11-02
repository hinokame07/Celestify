package com.music.spotui.ui.immersive.lyrics

import android.graphics.Bitmap
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the actual Android SurfaceTexture, EGL driver and resize callback. */
@RunWith(AndroidJUnit4::class)
class WarpSurfaceDeviceTest {
    @get:Rule val ui = createComposeRule()

    @Test
    fun shaderCoversBothEdgesAfterResize() {
        val cover =
            Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888).apply {
                eraseColor(0xffcc9988.toInt())
            }
        var wide by mutableStateOf(false)
        var view: WarpTexture? = null
        var failed = false
        ui.setContent {
            AndroidView(
                factory = { ctx -> WarpTexture(ctx) { failed = true }.also { view = it } },
                modifier =
                    Modifier.requiredSize(if (wide) 192.dp else 96.dp, if (wide) 96.dp else 192.dp),
                update = { it.display(cover, 1f, 1f) },
                onRelease = { it.release() },
            )
        }
        for (landscape in listOf(false, true)) {
            ui.runOnIdle { wide = landscape }
            ui.waitUntil(8000) {
                ui.runOnIdle {
                    val surface = view!!
                    check(!failed) { "Android EGL failed to render" }
                    if (!surface.isAvailable || (surface.width > surface.height) != landscape) false
                    else {
                        val bitmap = surface.getBitmap(16, 16)
                        bitmap != null &&
                            listOf(0 to 0, 15 to 0, 0 to 15, 15 to 15, 8 to 8).all { (x, y) ->
                                (bitmap.getPixel(x, y) and 0xffffff) != 0
                            }
                    }
                }
            }
        }
    }
}
