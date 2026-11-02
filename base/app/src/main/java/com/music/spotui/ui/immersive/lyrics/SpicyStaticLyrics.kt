/*
 * Static-lyrics presentation for Celestify's Spicy Lyrics port.
 * Unsynchronised text deliberately has no playback animation, dimming, blur, glow or seeking.
 */
package com.music.spotui.ui.immersive.lyrics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.music.spotui.ui.immersive.Immersive
import com.tx24.spicyplayer.lyrics.spicy.models.FooterLine
import com.tx24.spicyplayer.lyrics.spicy.models.Line

internal fun spicyStaticLineText(line: Line, romanize: Boolean): String =
    line.words
        .mapIndexed { index, word ->
            val value = if (romanize) word.romanizedText ?: word.text else word.text
            (if (index > 0 && !word.isPartOfWord) " " else "") + value
        }
        .joinToString("")
        .trim()

/** Plain reading mode for provider lyrics that contain no timestamps. */
@Composable
internal fun SpicyStaticLyrics(
    lines: List<Line>,
    footer: List<FooterLine>,
    romanize: Boolean,
    scale: Float,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier) {
        val tablet = maxWidth >= 700.dp
        val horizontal = if (tablet) 44.dp else 20.dp
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding =
                PaddingValues(horizontal = horizontal, vertical = if (tablet) 42.dp else 28.dp),
            verticalArrangement = Arrangement.spacedBy(if (tablet) 22.dp else 16.dp),
        ) {
            items(lines.filterNot { it.isInterlude }) { line ->
                val text = spicyStaticLineText(line, romanize)
                if (text.isNotBlank()) {
                    val align=if(line.oppositeAligned) TextAlign.End else TextAlign.Start
                    Text(
                        text = text,
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = align,
                        style =
                            Immersive.Lyric.copy(
                                color = Color.White,
                                fontSize = Immersive.Lyric.fontSize * scale,
                                lineHeight = Immersive.Lyric.lineHeight * scale,
                            ),
                    )
                    line.translation?.takeIf(String::isNotBlank)?.let { translated ->
                        Text(text = translated, modifier=Modifier.fillMaxWidth(), textAlign=align, style = Immersive.Body.copy(color = Color.White))
                    }
                }
            }
            items(footer) { credit ->
                Text(credit.text, style = Immersive.Caption.copy(color = Color.White))
            }
        }
    }
}
