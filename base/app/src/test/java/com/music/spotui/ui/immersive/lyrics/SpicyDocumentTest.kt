package com.music.spotui.ui.immersive.lyrics

import com.music.spotui.data.entity.LyricLine
import com.music.spotui.data.entity.LyricWord
import com.music.spotui.data.entity.Lyrics
import com.tx24.spicyplayer.lyrics.spicy.models.Line
import com.tx24.spicyplayer.lyrics.spicy.models.LyricsType
import com.tx24.spicyplayer.lyrics.spicy.models.Word
import org.junit.Assert.*
import org.junit.Test

class SpicyDocumentTest {
    @Test fun desktopDocumentKeepsFragmentTimesAndBackingVoiceGroups() {
        val lead = Line(listOf(Word("Hel", 1000, 1225), Word("lo", 1225, 1600, isPartOfWord=true)),1000,2000,groupId=5,oppositeAligned=true)
        val back = Line(listOf(Word("oh",1250,1800)),1250,1800,groupId=5,role=com.tx24.spicyplayer.lyrics.spicy.models.LineRole.BACKGROUND)
        val doc=com.tx24.spicyplayer.lyrics.spicy.models.LyricsDocument(listOf(lead,back))
        val json=desktopLyrics(doc.lines,doc)
        assertEquals("Syllable",json.getString("Type"))
        val group=json.getJSONArray("Content").getJSONObject(0)
        val words=group.getJSONObject("Lead").getJSONArray("Syllables")
        assertTrue(group.getBoolean("OppositeAligned"))
        assertTrue(words.getJSONObject(0).getBoolean("IsPartOfWord"))
        assertFalse(words.getJSONObject(1).getBoolean("IsPartOfWord"))
        assertEquals(1.225,words.getJSONObject(1).getDouble("StartTime"),.00001)
        assertEquals(1.25,group.getJSONArray("Background").getJSONObject(0).getDouble("StartTime"),.00001)
    }
    @Test fun staticLyricsStayStaticAndPreserveText() {
        val doc = Lyrics(listOf(LyricLine(0, "A whole line")), false).spicyDocument(9000)
        assertEquals(LyricsType.Static, doc.type)
        assertEquals("A whole line", doc.lines.single().words.single().text)
    }

    @Test fun staticReaderRebuildsWordsWithoutInventingTimingOrEffects() {
        val line = Line(listOf(
            Word("Hello", 0, 0, romanizedText = "Helo"),
            Word("world", 0, 0),
            Word("!", 0, 0, isPartOfWord = true),
        ), 0, 0)
        assertEquals("Hello world!", spicyStaticLineText(line, romanize = false))
        assertEquals("Helo world!", spicyStaticLineText(line, romanize = true))
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
