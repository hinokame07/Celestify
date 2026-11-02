package com.music.spotui.ui.immersive

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArtworkAccentTest {
    @Test fun nearBlackAndMonochromeStayNeutral() {
        for (seed in listOf(Color.Black, Color.DarkGray, Color.White)) {
            val accent = readableArtworkAccent(seed)
            assertEquals(accent.red, accent.blue, 0.01f)
            assertEquals(accent.red, accent.green, 0.01f)
            assertTrue(accent.luminance() >= 0.47f)
        }
    }

    @Test fun darkChromaticArtRetainsItsDominantChannel() {
        val red = readableArtworkAccent(Color(0xFF660610))
        val blue = readableArtworkAccent(Color(0xFF071069))
        assertTrue(red.red > red.blue && blue.blue > blue.red)
        assertTrue(red.luminance() >= 0.47f && blue.luminance() >= 0.47f)
    }
}
