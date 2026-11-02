package com.music.spotui.ui.immersive.lyrics

import com.music.spotui.data.entity.LyricLine
import com.music.spotui.data.entity.LyricWord
import com.music.spotui.data.entity.Lyrics
import com.tx24.spicyplayer.lyrics.spicy.models.LyricsType
import org.junit.Assert.*
import org.junit.Test

class SpicyDocumentTest {
    @Test fun staticLyricsStayStaticAndPreserveText() {
        val doc = Lyrics(listOf(LyricLine(0, "A whole line")), false).spicyDocument(9000)
        assertEquals(LyricsType.Static, doc.type)
        assertEquals("A whole line", doc.lines.single().words.single().text)
    }

    @Test fun partsOfAWordJoinButSeparateWordsDoNot() {
        val row = LyricLine(100, "Hello there", listOf(
            LyricWord(100, 200, "Hel"), LyricWord(200, 400, "lo"), LyricWord(500, 700, "there")
        ))
        val doc = Lyrics(listOf(row), true).spicyDocument(800)
        assertEquals(LyricsType.Syllable, doc.type)
        assertEquals(listOf(false, true, false), doc.lines.single().words.map { it.isPartOfWord })
        assertEquals(listOf(100L, 200L, 500L), doc.lines.single().words.map { it.startMs })
    }

    @Test fun incompleteTimestampsDoNotStretchWordsToTheNextLine() {
        val lyrics = Lyrics(listOf(LyricLine(100, "Now", listOf(LyricWord(100, 0, "Now"))), LyricLine(4000, "Then")), true)
        val doc = lyrics.spicyDocument(5000)
        assertEquals(100L, doc.lines.first().words.single().endMs)
        assertTrue(doc.lines.last().lineTimed)
    }
}
