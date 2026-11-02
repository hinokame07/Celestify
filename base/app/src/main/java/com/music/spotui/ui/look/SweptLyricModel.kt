/*
 * Adapted from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0-or-later,
 * shared/src/jvmSharedMain/kotlin/com/music/bitchord/data/lyrics/LyricLine.kt at edc1e6f.
 * Modified for Myspoti, 2026-10.
 *
 * Changes: renamed SweptLine / SweptWord / SweptSyllable so they do not clash with Myspoti's
 * own lyric entities, which they are built from (see toSwept). The answering vocal, duet
 * sides, translation timing and character stripping are left out for now.
 */
package com.music.spotui.ui.look

/**
 * One word of a line, with the stretch of the song it is sung over.
 *
 * Some sources split long words into syllables. The word is still the unit
 * the line is laid out, lifted and lit in, so [startMs] is the first
 * syllable's start and [endMs] the last one's end; the sweep follows
 * [syllables] where there are some. Empty for a word nobody split, which is
 * most of them — the word is then its own single syllable.
 */
data class SweptWord(
    val startMs: Long,
    val endMs: Long,
    val text: String,
    val syllables: List<SweptSyllable> = emptyList(),
) {
    /**
     * How many of [text]'s characters have been sung at [positionMs], as a
     * fraction. Each syllable fills its own characters over its own time, and
     * a pause between two of them rests on the boundary rather than creeping
     * into the next one before it is sung.
     */
    fun charsSungAt(positionMs: Long): Float {
        if (positionMs <= startMs) return 0f
        if (positionMs >= endMs) return text.length.toFloat()
        if (syllables.isEmpty()) {
            val span = (endMs - startMs).coerceAtLeast(1L)
            return (positionMs - startMs).toFloat() / span * text.length
        }
        for (syllable in syllables) {
            if (positionMs < syllable.startMs) return syllable.startChar.toFloat()
            if (positionMs < syllable.endMs) {
                val span = (syllable.endMs - syllable.startMs).coerceAtLeast(1L)
                val through = (positionMs - syllable.startMs).toFloat() / span
                return syllable.startChar + through * (syllable.endChar - syllable.startChar)
            }
        }
        return text.length.toFloat()
    }
}

/**
 * One separately timed piece of a [SweptWord]: the characters [startChar]
 * until [endChar] of the word's text, sung from [startMs] to [endMs].
 */
data class SweptSyllable(
    val startMs: Long,
    val endMs: Long,
    val startChar: Int,
    val endChar: Int,
)

/**
 * One synced line. [timeMs] is when it starts; [words] is filled only when
 * the source carries word-level timing, otherwise the line highlights whole.
 * [sungUntilMs] is the line's own end where the source states one.
 */
data class SweptLine(
    val timeMs: Long,
    val text: String,
    val words: List<SweptWord> = emptyList(),
    val sungUntilMs: Long? = null,
) {
    val isGap: Boolean get() = text.isEmpty()

    val isWordSynced: Boolean get() = words.isNotEmpty()

    /**
     * Where each of [words] sits in [text], as character ranges.
     *
     * Walked from where the last one ended rather than searched from the start,
     * so a word repeated in the line lines up with its own occurrence — the
     * same walk [revealedChars] does, kept once because the rise reads it on
     * every frame of the line being sung rather than once as it passes.
     */
    val wordSpans: List<IntRange> by lazy(LazyThreadSafetyMode.NONE) {
        var offset = 0
        words.map { word ->
            val start = text.indexOf(word.text, offset).takeIf { it >= 0 } ?: offset
            val end = start + word.text.length
            offset = end
            start until end
        }
    }

    /**
     * Where each separately timed piece of the line sits in [text]: a word's
     * syllables where the source split it, the word itself where it did not.
     * The sweep crosses each of these at a steady pace of its own.
     */
    val sweepSpans: List<IntRange> by lazy(LazyThreadSafetyMode.NONE) {
        words.flatMapIndexed { index, word ->
            val span = wordSpans[index]
            if (word.syllables.isEmpty()) {
                listOf(span)
            } else {
                word.syllables.map { (span.first + it.startChar) until (span.first + it.endChar) }
            }
        }
    }

    /**
     * Whether anything on this line is off the floor at [positionMs].
     *
     * Two comparisons, so the lines that are not being sung — which is every
     * line but one, on every frame — settle the question without walking their
     * words to find out that none of them have moved.
     */
    fun isLifted(positionMs: Long): Boolean {
        val first = words.firstOrNull() ?: return false
        if (positionMs <= first.startMs) return false
        // A word animated letter by letter runs on past the ordinary fall — its
        // last letter only starts moving as the word ends. Stopping at the fall
        // would drop that letter back to the line mid-swell.
        return positionMs < words.last().endMs + RISE_MS || isGrowing(positionMs)
    }

    /**
     * The stretch of the song over which anything drawn for this line moves —
     * the sweep, the lift and its settle, a held word's letters — from
     * [animatesFromMs] to [animatesUntilMs]. Before it the line is drawn
     * unsung, after it sung and at rest, and either way exactly the same on
     * every frame — which is what lets a line outside it stop listening to the clock.
     */
    val animatesFromMs: Long by lazy(LazyThreadSafetyMode.NONE) {
        minOf(timeMs, words.firstOrNull()?.startMs ?: timeMs)
    }

    /** See [animatesFromMs]. */
    val animatesUntilMs: Long by lazy(LazyThreadSafetyMode.NONE) {
        val settled = words.lastOrNull()?.let { it.endMs + RISE_MS.toLong() } ?: endMs
        val grown = growingWords.maxOfOrNull { it.restsAtMs } ?: Long.MIN_VALUE
        maxOf(endMs, settled, grown)
    }

    /**
     * How far the word covering [positionMs] has lifted, 0..1.
     *
     * The words don't only light up, they rise as they land and settle back
     * once they are past — the lift travelling along the line is most of what
     * separates singing from a bar sliding across the text.
     *
     * How high a word goes is set by how long it is held — see [liftHeight]:
     * patter barely leaves the line and a carried note goes all the way up.
     * It rises over its own length, so a quick word's small lift is also a
     * quick one, and settles back over [RISE_MS] from its end.
     */
    fun wordLift(index: Int, positionMs: Long): Float {
        val word = words.getOrNull(index) ?: return 0f
        val riseMs = (word.endMs - word.startMs).toFloat().coerceIn(RISE_MIN_MS, RISE_MS)
        val rising = ((positionMs - word.startMs) / riseMs).coerceIn(0f, 1f)
        val falling = (1f - (positionMs - word.endMs) / RISE_MS).coerceIn(0f, 1f)
        return liftHeight(word) * smooth(minOf(rising, falling))
    }

    /** Whether anything actually told us when the singing stops, rather than only when it starts. */
    val hasKnownEnd: Boolean get() = words.isNotEmpty() || sungUntilMs != null

    /**
     * When the last word finishes — or the line's own end where the source
     * gave one, or [timeMs] when nothing did. Check [hasKnownEnd] before
     * reading a silence out of this.
     */
    val endMs: Long
        get() = words.lastOrNull()?.endMs ?: sungUntilMs ?: timeMs

    /**
     * How far through the line the singing has got, as a fractional index
     * into [text]. The sweep reveals up to this character.
     *
     * Within a word it interpolates across that word's own span, so a held
     * note draws slowly and a rattled-off one snaps. Whitespace between two
     * words is credited to the gap between them: it fills as the singer moves
     * on rather than jumping ahead of the next word's first letter.
     */
    fun revealedChars(positionMs: Long): Float {
        if (words.isEmpty()) return if (positionMs >= timeMs) text.length.toFloat() else 0f
        var offset = 0
        words.forEachIndexed { index, word ->
            // Where this word sits in [text]. Built by walking rather than
            // searching, so a word repeated in the line still lines up.
            val start = text.indexOf(word.text, offset).takeIf { it >= 0 } ?: offset
            val end = start + word.text.length
            if (positionMs < word.startMs) return start.toFloat()
            if (positionMs < word.endMs) return start + word.charsSungAt(positionMs)
            // Past this word: the trailing space fills over the pause before
            // the next one, so the highlight keeps creeping instead of resting
            // on the word's last letter.
            val next = words.getOrNull(index + 1)
            if (next != null && positionMs < next.startMs) {
                val gapStart = text.indexOf(next.text, end).takeIf { it >= 0 } ?: end
                val pause = (next.startMs - word.endMs).coerceAtLeast(1L)
                val through = (positionMs - word.endMs).toFloat() / pause
                return end + through * (gapStart - end)
            }
            offset = end
        }
        return text.length.toFloat()
    }

    /**
     * How much of a word's lift is left at [positionMs] — its full
     * [liftHeight] while it is being sung, easing to 0 over [RISE_MS] once it
     * is past. Carries the height so a letter-by-letter word comes to rest at
     * exactly the lift [wordLift] hands it over to.
     */
    fun wordFall(index: Int, positionMs: Long): Float {
        val word = words.getOrNull(index) ?: return 0f
        val falling = (1f - (positionMs - word.endMs) / RISE_MS).coerceIn(0f, 1f)
        return liftHeight(word) * smooth(falling)
    }

    /**
     * The words held long enough to be worth animating letter by letter: the
     * one moment in a line where there is time to see anything happen to a
     * word. Each letter of one swells, lifts and lights in turn — see
     * [GrowingWord] for the shape of it. Rare by design.
     */
    val growingWords: List<GrowingWord> by lazy(LazyThreadSafetyMode.NONE) {
        words.mapIndexedNotNull { index, word ->
            if (word.canGrow()) GrowingWord(index, word, index == words.lastIndex) else null
        }
    }

    /** The letter-by-letter treatment for word [index], where it has earned one. */
    fun growingAt(index: Int): GrowingWord? =
        growingWords.firstOrNull { it.index == index }

    /**
     * Whether any word on this line is mid-flight at [positionMs]. Answered
     * without touching the words themselves, so the lines that have no held
     * word — which is most of them — settle it in a comparison.
     */
    fun isGrowing(positionMs: Long): Boolean = growingWords.any {
        positionMs >= it.startMs && positionMs <= it.restsAtMs
    }
}

/** Only interpolate a word when its source supplies an end timestamp. */
fun com.music.spotui.data.entity.LyricLine.toSwept(nextLineMs: Long? = null): SweptLine {
    val swept = words.orEmpty().map { word ->
        SweptWord(word.startMs, word.endMs.coerceAtLeast(word.startMs), word.text.trim())
    }.filter { it.text.isNotEmpty() }
    return SweptLine(timeMs, text, swept, sungUntilMs = nextLineMs)
}

/** Where one letter of a [GrowingWord] is, filled in by [GrowingWord.sampleInto]. */
class CharGrowth {
    /** Swell, about the letter's own centre. 1 is the letter as laid out. */
    var scale: Float = 1f

    /** Lean away from the middle of the word, in ems. */
    var shift: Float = 0f

    /** Lift, in multiples of the ordinary sung-word rise. */
    var rise: Float = 0f

    /** Bloom, 0..1, at its own peak partway up rather than at the top. */
    var bloom: Float = 0f
}

/** How long a word takes to rise, and to settle back down once it is past. */
private const val RISE_MS = 700f

/** The quickest a word ever rises: a 90 ms syllable snapping up reads as a twitch. */
private const val RISE_MIN_MS = 250f

/**
 * How far up a word goes, as a share of the full lift, from how long it is held.
 *
 * A word sung in [LIFT_QUICK_MS] or less only nudges up by [LIFT_FLOOR]; one
 * held for [LIFT_HELD_MS] or more goes the whole way. Eased between the two, so
 * the words of an ordinary line differ from one another by a little rather than
 * falling into "up" and "not up".
 */
private fun liftHeight(word: SweptWord): Float {
    val held = (word.endMs - word.startMs).toFloat()
    val through = ((held - LIFT_QUICK_MS) / (LIFT_HELD_MS - LIFT_QUICK_MS)).coerceIn(0f, 1f)
    return LIFT_FLOOR + (1f - LIFT_FLOOR) * smooth(through)
}

private const val LIFT_QUICK_MS = 150f
private const val LIFT_HELD_MS = 900f
private const val LIFT_FLOOR = 0.25f

/** Ease in and out of the ends, so the lift has no corners on it. */
private fun smooth(fraction: Float) = fraction * fraction * (3f - 2f * fraction)

/** Avoid separating combining marks, emoji and joined scripts into broken glyphs. */
private fun SweptWord.canGrow() = text.length in 2..7 && endMs - startMs >= 1000 &&
    text.all { it.isLetter() && (it in 'A'..'ɏ' || it in 'Ͱ'..'ԯ') }
