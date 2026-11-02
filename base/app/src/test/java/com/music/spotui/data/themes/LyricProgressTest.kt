package com.music.spotui.data.themes
import com.music.spotui.data.entity.LyricTiming
import com.music.spotui.data.entity.LyricWord
import org.junit.Assert.*
import org.junit.Test
class LyricProgressTest {
    @Test fun playbackTimestampControlsWordFill() {
        val word = LyricWord(1000, 2000, "Moon")
        assertEquals(0f, LyricTiming.wordProgress(word, 500), 0f)
        assertEquals(.5f, LyricTiming.wordProgress(word, 1500), 0f)
        assertEquals(1f, LyricTiming.wordProgress(word, 2500), 0f)
    }
    @Test fun missingEndNeverFabricatesDuration() {
        val word = LyricWord(1000, 0, "Moon")
        assertEquals(0f, LyricTiming.wordProgress(word, 999), 0f)
        assertEquals(1f, LyricTiming.wordProgress(word, 1000), 0f)
    }
}
