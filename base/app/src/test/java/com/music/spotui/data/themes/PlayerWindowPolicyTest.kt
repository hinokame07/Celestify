package com.music.spotui.data.themes
import com.music.spotui.ui.immersive.player.PlayerWindowPolicy
import org.junit.Assert.*
import org.junit.Test
class PlayerWindowPolicyTest {
    @Test fun compactStandardLargePhones() {
        assertTrue(PlayerWindowPolicy.compact(320f))
        assertFalse(PlayerWindowPolicy.compact(390f))
        assertTrue(PlayerWindowPolicy.scrollControls(390f, 600f, 1f))
        assertTrue(PlayerWindowPolicy.scrollControls(430f, 900f, 1.5f))
        assertFalse(PlayerWindowPolicy.scrollControls(430f, 900f, 1f))
        assertTrue(PlayerWindowPolicy.scrollControls(800f, 360f, 1f, 360f))
        assertFalse(PlayerWindowPolicy.scrollControls(800f, 360f, 1f, 600f))
    }
    @Test fun tabletGeometryNeverUsesPhoneAdaptations() {
        for (width in listOf(600f, 800f, 1280f)) {
            assertFalse(PlayerWindowPolicy.compact(width))
            assertFalse(PlayerWindowPolicy.scrollControls(width, 480f, 2f))
        }
    }
}
