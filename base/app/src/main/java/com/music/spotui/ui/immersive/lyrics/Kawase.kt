package com.music.spotui.ui.immersive.lyrics

import kotlin.math.floor

/** Kawarp 1.3.1 (MIT). Four bilinear taps per pass on its fixed 128×128 artwork texture. */
internal object Kawase {
    const val SIZE = 128

    fun blur(pixels: IntArray): IntArray {
        require(pixels.size == SIZE * SIZE)
        var src = pixels.copyOf()
        var dst = IntArray(src.size)
        val low = IntArray(SIZE)
        val high = IntArray(SIZE)
        val nextLow = IntArray(SIZE)
        val nextHigh = IntArray(SIZE)
        repeat(8) { pass ->
            for (i in 0 until SIZE) {
                val left = floor(i - pass - .5).toInt()
                val right = floor(i + pass + .5).toInt()
                low[i] = left.coerceIn(0, SIZE - 1)
                nextLow[i] = (left + 1).coerceIn(0, SIZE - 1)
                high[i] = right.coerceIn(0, SIZE - 1)
                nextHigh[i] = (right + 1).coerceIn(0, SIZE - 1)
            }
            // At half-pixel offsets the four bilinear taps have sixteen equal weights.
            for (y in 0 until SIZE) {
                val rows =
                    intArrayOf(low[y] * SIZE, nextLow[y] * SIZE, high[y] * SIZE, nextHigh[y] * SIZE)
                for (x in 0 until SIZE) {
                    var rb = 0L
                    var g = 0
                    for (row in rows) {
                        val a = src[row + low[x]]
                        val b = src[row + nextLow[x]]
                        val c = src[row + high[x]]
                        val d = src[row + nextHigh[x]]
                        rb +=
                            (a and 0xff00ff) +
                                (b and 0xff00ff) +
                                (c and 0xff00ff) +
                                (d and 0xff00ff)
                        g += (a and 0xff00) + (b and 0xff00) + (c and 0xff00) + (d and 0xff00)
                    }
                    dst[y * SIZE + x] =
                        (0xff shl 24) or
                            (((rb + 0x080008).toInt() ushr 4) and 0xff00ff) or
                            (((g + 0x800) ushr 4) and 0xff00)
                }
            }
            val old = src
            src = dst
            dst = old
        }
        return src
    }
}
