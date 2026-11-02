package com.music.spotui.ui.immersive.lyrics

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.music.spotui.ui.immersive.player.*
import com.tx24.spicyplayer.lyrics.spicy.RenderConfig
import com.tx24.spicyplayer.lyrics.spicy.ScrollConfig
import com.tx24.spicyplayer.lyrics.spicy.canvas.LyricsView
import com.tx24.spicyplayer.lyrics.spicy.models.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [33], qualifiers = "en-w900dp-h900dp-mdpi", application = Application::class)
class NativeCinemaTest {
    @get:Rule val ui = createComposeRule()

    private fun frames(ms: Long = 300) {
        ui.waitForIdle()
        ui.mainClock.advanceTimeBy(ms)
        org.robolectric.shadows.ShadowLooper.idleMainLooper(
            32,
            java.util.concurrent.TimeUnit.MILLISECONDS,
        )
        ui.mainClock.advanceTimeByFrame()
        ui.waitForIdle()
    }

    @Before
    fun provideThemePreferences() {
        // Theme preferences need an Application. Keep the Spotify session out of this UI test.
        com.music.spotui.di.Graph::class.java.getDeclaredField("app").apply {
            isAccessible = true
            set(null, org.robolectric.RuntimeEnvironment.getApplication())
        }
    }

    @Test
    fun clapperboardOpensAndClosesTheNativeDialogTwice() {
        val vm = com.music.spotui.ui.viewmodel.LyricsViewModel()
        var recording by mutableStateOf("track-A")
        val song =
            com.music.spotui.data.entity.Lyrics(
                listOf(com.music.spotui.data.entity.LyricLine(0, "Untimed verse")),
                false,
            )
        ui.mainClock.autoAdvance = false
        ui.setContent {
            SpicyStage(
                recording,
                com.music.spotui.ui.viewmodel.LyricsViewModel.State.Loaded(song),
                vm,
                Modifier.fillMaxSize(),
                PaddingValues(0.dp),
                remember { mutableStateOf(false) },
            )
        }
        frames()
        repeat(2) {
            ui.onNodeWithContentDescription("Open Cinema View").performTouchInput { click() }
            frames()
            ui.onNodeWithTag("cinema").assertIsDisplayed()
            val screen = ui.onNodeWithTag("cinema").fetchSemanticsNode().id
            ui.runOnIdle { recording = if (recording == "track-A") "track-B" else "track-A" }
            frames()
            assertEquals(screen, ui.onNodeWithTag("cinema").fetchSemanticsNode().id)
            ui.onNodeWithTag("cinema-close").performTouchInput { click() }
            frames()
            ui.onNodeWithTag("cinema").assertDoesNotExist()
        }
    }

    @Test
    fun fullPlayerKeepsTransportReachableAcrossSizes() {
        var wide by mutableStateOf(false)
        var plays = 0
        var closed = false
        ui.mainClock.autoAdvance = false
        ui.setContent {
            val state =
                ImmersivePlayerState(
                    title = "Nightfall",
                    artist = "Test recording",
                    album = "Orbit",
                    durationMs = 80_000,
                )
            Box(Modifier.requiredSize(if (wide) 840.dp else 390.dp, if (wide) 390.dp else 820.dp)) {
                ImmersivePlayer(
                    state,
                    ImmersivePlayerActions(playPause = { plays++ }, close = { closed = true }),
                )
            }
        }
        frames(900)
        ui.onNodeWithText("Nightfall").assertIsDisplayed()
        ui.onNodeWithContentDescription("Play").performTouchInput { click() }
        ui.runOnIdle {
            assertEquals(1, plays)
            wide = true
        }
        frames(500)
        ui.onNodeWithContentDescription("Play").assertIsDisplayed().performTouchInput { click() }
        frames()
        ui.onNodeWithContentDescription("Close the player").performTouchInput { click() }
        ui.runOnIdle {
            assertEquals(2, plays)
            assertTrue(closed)
        }
    }

    @Test
    fun touchTransportLyricsAndRotate() {
        val lines =
            (0 until 40).map { i ->
                val start = i * 2000L
                Line(
                    listOf(
                        Word("Verse", start, start + 900),
                        Word(i.toString(), start + 900, start + 1950),
                    ),
                    start,
                    start + 1950,
                )
            }
        var wide by mutableStateOf(false)
        var left by mutableStateOf(false)
        var controls by mutableStateOf(true)
        var playing by mutableStateOf(false)
        var position = 8000L
        var lastLyric = -1L
        var previous = 0
        var next = 0
        var closed = false
        val area = ui.onNodeWithTag("cinema-lyrics")
        ui.mainClock.autoAdvance = false
        ui.setContent {
            val player =
                ImmersivePlayerState(
                    title = "Nightfall",
                    artist = "Test recording",
                    playing = playing,
                    positionMs = { position },
                    durationMs = 80_000,
                )
            Box(Modifier.requiredSize(if (wide) 840.dp else 390.dp, if (wide) 390.dp else 820.dp)) {
                NativeCinemaLayout(
                    player,
                    left,
                    controls,
                    { left = !left },
                    { controls = !controls },
                    { closed = true },
                    {},
                    artwork = { Box(it.background(Color.DarkGray)) },
                    lyrics = { box ->
                        LyricsView(
                            lines,
                            "native-touch",
                            currentTimeMs = { position },
                            onSeekWord = {
                                lastLyric = it
                                position = it
                            },
                            modifier = box,
                            config =
                                RenderConfig(
                                    simpleLyricsMode = false,
                                    minimalLyricsMode = false,
                                    scroll = ScrollConfig(seekFadeCompensation = false),
                                ),
                            lyricsType = LyricsType.Syllable,
                            isPlaying = playing,
                        )
                    },
                    transport = {
                        Column {
                            PlayerScrubber(player, { position = it })
                            TransportRow(
                                playing,
                                false,
                                true,
                                { previous++ },
                                { playing = !playing },
                                { next++ },
                            )
                        }
                    },
                )
            }
        }
        fun button(label: String) {
            ui.onNodeWithContentDescription(label).performTouchInput { click() }
            frames()
        }
        frames(1500)
        button("Play")
        assertTrue(playing)
        button("Pause")
        assertFalse(playing)
        button("Previous")
        button("Next")
        assertEquals(1, previous)
        assertEquals(1, next)
        ui.onNodeWithContentDescription("Playback position").performTouchInput {
            swipe(Offset(width * .2f, centerY), Offset(width * .62f, centerY), 300)
        }
        frames()
        assertTrue("seek was $position", position in 47_000..53_000)
        ui.onNodeWithTag("cinema-controls").performTouchInput { click() }
        frames()
        ui.onNodeWithContentDescription("Play").assertDoesNotExist()
        area.performTouchInput { swipeUp() }
        frames(900)
        for (n in 2..8) {
            area.performTouchInput { click(Offset(width * .45f, height * n / 10f)) }
            frames(50)
            if (lastLyric >= 0) break
        }
        assertTrue("Touch must reach a timed lyric", lastLyric >= 0 && lastLyric % 2000 == 0L)
        ui.runOnIdle { wide = true }
        frames()
        val before = area.fetchSemanticsNode().boundsInRoot
        ui.onNodeWithTag("cinema-swap").performTouchInput { click() }
        frames()
        val after = area.fetchSemanticsNode().boundsInRoot
        assertTrue(
            "swap=$left before=$before after=$after root=" +
                ui.onRoot().fetchSemanticsNode().boundsInRoot,
            left && after.left < before.left,
        )
        ui.onNodeWithTag("cinema-controls").performTouchInput { click() }
        frames()
        button("Play")
        ui.onNodeWithTag("cinema-close").performTouchInput { click() }
        frames()
        assertTrue(closed)
    }
}
