package com.music.spotui.ui.immersive.player

/** Phone adjustments never apply to windows at least 600 dp wide. */
internal object PlayerWindowPolicy {
    fun compact(width: Float) = width < 360f
    fun scrollControls(width: Float, height: Float, fontScale: Float, smallestWidth: Float = width) =
        (width < 600f && height < 650f) || (smallestWidth < 600f && (height < 650f || fontScale > 1.3f))
}
