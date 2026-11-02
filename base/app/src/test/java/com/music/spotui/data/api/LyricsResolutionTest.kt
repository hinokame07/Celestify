package com.music.spotui.data.api

import com.music.spotui.data.entity.Lyrics
import com.music.spotui.data.entity.LyricLine
import com.music.spotui.data.entity.LyricWord
import com.music.spotui.ui.look.toSwept
import org.junit.Assert.*
import org.junit.Test

class LyricsResolutionTest {
    private val plain = Lyrics(listOf(LyricLine(0, "Intro")), false)
    private val timed = Lyrics(listOf(LyricLine(500, "Intro")), true)

    @Test fun plainAnswerDoesNotHideTimedFallback() {
        assertSame(timed, LyricsApi.preferTimed(plain) { timed })
        assertSame(plain, LyricsApi.preferTimed(plain) { null })
        assertSame(timed, LyricsApi.preferTimed(timed) { error("unnecessary request") })
    }

    @Test fun emptyWordsDoNotQualifyAsKaraoke() {
        assertFalse(Lyrics(listOf(LyricLine(0, "Intro", emptyList())), true).wordSynced)
    }

    @Test fun timestampOnlyWordDoesNotSweepAcrossThePause() {
        val line = LyricLine(0, "One two", listOf(LyricWord(0, 0, "One"), LyricWord(2000, 2800, "two")))
        val swept = line.toSwept(6000)
        assertEquals(0L, swept.words.first().endMs)
        assertEquals(2800L, swept.words.last().endMs)
    }
}
