package com.music.spotui.data.entity

/** Timing shared by the player panel and full-screen lyrics. */
object LyricTiming {
    /** Positive offset delays a lyric relative to the sound. */
    fun position(playbackMs: Long, outputLagMs: Long, offsetMs: Int): Long =
        (playbackMs - outputLagMs - offsetMs).coerceAtLeast(0L)

    fun seekPosition(lineMs: Long, offsetMs: Int): Long = (lineMs + offsetMs).coerceAtLeast(0L)

    fun activeLine(lyrics: Lyrics, positionMs: Long): Int {
        if (!lyrics.synced) return -1
        var lo = 0
        var hi = lyrics.lines.lastIndex
        var found = -1
        while (lo <= hi) {
            val middle = (lo + hi) ushr 1
            if (lyrics.lines[middle].timeMs <= positionMs) { found = middle; lo = middle + 1 }
            else hi = middle - 1
        }
        return found
    }

    /** Returns -1 if this source does not supply actual word stamps. */
    fun activeWord(line: LyricLine, positionMs: Long): Int =
        line.words.orEmpty().indexOfLast { it.startMs <= positionMs }

    /** Continuous fill only when an actual word duration is present; otherwise a timestamp step. */
    fun wordProgress(word: LyricWord, positionMs: Long): Float = when {
        positionMs < word.startMs -> 0f
        word.endMs <= word.startMs -> 1f
        else -> ((positionMs - word.startMs).toFloat() / (word.endMs - word.startMs)).coerceIn(0f, 1f)
    }
}
