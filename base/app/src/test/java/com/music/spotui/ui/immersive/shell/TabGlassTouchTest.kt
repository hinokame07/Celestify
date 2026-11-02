package com.music.spotui.ui.immersive.shell

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [33], qualifiers = "en-w480dp-h480dp-mdpi", application = Application::class)
class TabGlassTouchTest {
    @get:Rule val ui = createComposeRule()

    @Test
    fun pressHoldSlideAndTapKeepFeedbackAndCommitOnce() {
        var selected by mutableStateOf("Home")
        val visits = mutableListOf<String>()
        ui.mainClock.autoAdvance = false
        ui.setContent {
            Box(Modifier.requiredWidth(320.dp).background(Color(0xff121826)).testTag("strip")) {
                FloatingTabBar(selectedTabKey = selected) {
                    listOf("Home", "Library").forEach { name ->
                        tab(
                            name,
                            title = { Text(name, color = Color.White) },
                            icon = { Spacer(Modifier.size(20.dp)) },
                            onClick = {
                                selected = name
                                visits += name
                            },
                        )
                    }
                }
            }
        }
        fun frames(ms: Long) {
            ui.waitForIdle()
            ui.mainClock.advanceTimeBy(ms)
            org.robolectric.shadows.ShadowLooper.idleMainLooper(
                32,
                java.util.concurrent.TimeUnit.MILLISECONDS,
            )
            ui.mainClock.advanceTimeByFrame()
            ui.waitForIdle()
        }
        val strip = ui.onNodeWithTag("strip")
        fun pixels(): IntArray {
            val image =
                android.graphics.Bitmap.createScaledBitmap(
                    strip.captureToImage().asAndroidBitmap(),
                    80,
                    16,
                    true,
                )
            return IntArray(80 * 16).also { image.getPixels(it, 0, 80, 0, 0, 80, 16) }
        }
        frames(300)
        val rest = pixels()
        strip.performTouchInput { down(Offset(width * .24f, centerY)) }
        frames(1100)
        assertFalse(rest.contentEquals(pixels()))
        assertTrue(visits.isEmpty())
        val held = pixels()
        strip.performTouchInput { moveTo(Offset(width * .76f, centerY)) }
        frames(400)
        assertFalse(held.contentEquals(pixels()))
        assertTrue(visits.isEmpty())
        strip.performTouchInput { up() }
        frames(700)
        assertEquals(listOf("Library"), visits)
        ui.onNodeWithText("Home").performTouchInput { click() }
        frames(700)
        assertEquals(listOf("Library", "Home"), visits)
        strip.performTouchInput {
            down(center)
            cancel()
        }
        frames(800)
        assertEquals(2, visits.size)
    }
}
