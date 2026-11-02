package com.music.spotui.ui.immersive.lyrics

import org.junit.Assert.*
import org.junit.Test

class KawaseTest {
    @Test
    fun uniformCoverKeepsItsColorAtEveryEdge() {
        val solid = IntArray(Kawase.SIZE * Kawase.SIZE) { 0xff4876af.toInt() }
        assertArrayEquals(solid, Kawase.blur(solid))
    }

    @Test
    fun blurPreservesOppositeEdgesAndBlendsTheCentre() {
        val n = Kawase.SIZE
        val pixels =
            IntArray(n * n) { if (it % n < n / 2) 0xffff0000.toInt() else 0xff0000ff.toInt() }
        val result = Kawase.blur(pixels)
        assertEquals(pixels.first(), result.first())
        assertEquals(pixels.last(), result.last())
        val mix = result[n / 2]
        assertTrue((mix ushr 16 and 255) in 20..230 && (mix and 255) in 20..230)
        assertEquals(0, mix ushr 8 and 255)
    }
}
