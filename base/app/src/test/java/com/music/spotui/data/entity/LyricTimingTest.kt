package com.music.spotui.data.entity

import org.junit.Assert.assertEquals
import org.junit.Test

class LyricTimingTest {
    private val timed = Lyrics(listOf(
        LyricLine(1000, "one", listOf(LyricWord(1000, 1400, "one"))),
        LyricLine(2200, "two", listOf(LyricWord(2200, 2600, "two"))),
    ), synced = true)

    @Test fun activeLineAndWordFollowActualStamps() {
        assertEquals(-1, LyricTiming.activeLine(timed, 999))
        assertEquals(0, LyricTiming.activeLine(timed, 1000))
        assertEquals(1, LyricTiming.activeLine(timed, 2200))
        assertEquals(-1, LyricTiming.activeWord(timed.lines[1], 2199))
        assertEquals(0, LyricTiming.activeWord(timed.lines[1], 2200))
    }

    @Test fun offsetAndAudioLagAreAppliedOnce() {
        assertEquals(950L, LyricTiming.position(1500, outputLagMs = 300, offsetMs = 250))
        assertEquals(1250L, LyricTiming.seekPosition(1000, offsetMs = 250))
        assertEquals(0L, LyricTiming.position(50, outputLagMs = 300, offsetMs = 0))
    }

    @Test fun plainLyricsNeverPretendToSynchronize() {
        val plain = Lyrics(listOf(LyricLine(0, "ordinary words")), synced = false)
        assertEquals(-1, LyricTiming.activeLine(plain, 9000))
        assertEquals(-1, LyricTiming.activeWord(plain.lines.single(), 9000))
    }
}
