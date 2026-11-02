package com.music.spotui.ui.immersive.lyrics

import android.content.Context
import android.net.Uri
import android.util.AtomicFile
import com.music.spotui.data.entity.Lyrics
import com.tx24.spicyplayer.lyrics.spicy.models.*
import com.tx24.spicyplayer.lyrics.spicy.parser.TtmlLyricsParser
import java.io.File
import java.security.MessageDigest

internal fun Lyrics.spicyDocument(duration: Long): LyricsDocument {
    val rich = ttml?.let { TtmlLyricsParser.parse(it.byteInputStream()) }
    if (rich != null && rich.lines.isNotEmpty()) {
        if (ttmlOffsetMs == 0L) return rich
        fun shift(t: Long) = (t + ttmlOffsetMs).coerceAtLeast(0L)
        return rich.copy(
            lines =
                rich.lines.map { line ->
                    if (line.untimed || rich.type == LyricsType.Static) line
                    else
                        line.copy(
                            startMs = shift(line.startMs),
                            endMs = shift(line.endMs),
                            words =
                                line.words.map { word ->
                                    word.copy(
                                        startMs = shift(word.startMs),
                                        endMs = shift(word.endMs),
                                        letters =
                                            word.letters.map {
                                                it.copy(
                                                    startMs = shift(it.startMs),
                                                    endMs = shift(it.endMs),
                                                )
                                            },
                                    )
                                },
                        )
                }
        )
    }
    val type =
        when {
            !synced -> LyricsType.Static
            wordSynced -> LyricsType.Syllable
            else -> LyricsType.Line
        }
    val rows =
        lines.mapIndexed { index, line ->
            val end =
                maxOf(
                    line.timeMs,
                    line.endMs ?: lines.getOrNull(index + 1)?.timeMs ?: duration,
                    line.words.orEmpty().maxOfOrNull { it.endMs } ?: line.timeMs,
                )
            var offset = 0
            val words =
                line.words.orEmpty().mapIndexedNotNull { i, w ->
                    val text =
                        w.text.trim().takeIf { it.isNotEmpty() } ?: return@mapIndexedNotNull null
                    val start = line.text.indexOf(text, offset).takeIf { it >= 0 } ?: offset
                    val joined = offset > 0 && start == offset
                    offset = start + text.length
                    val until =
                        if (w.endMs > w.startMs) w.endMs
                        else line.words?.getOrNull(i + 1)?.startMs ?: w.startMs
                    Word(text, w.startMs, maxOf(w.startMs, until), isPartOfWord = joined)
                }
            val gap = synced && (line.text.isBlank() || line.text.trim() == "♪")
            Line(
                if (gap) emptyList()
                else words.ifEmpty { listOf(Word(line.text, line.timeMs, end)) },
                line.timeMs,
                end,
                role = if (gap) LineRole.INTERLUDE else LineRole.LEAD,
                lineTimed = words.isEmpty(),
                agent = line.singer,
                oppositeAligned = line.oppositeAligned,
            )
        }
    return LyricsDocument(
        rows,
        LyricsFooter(provenance = provider?.let { LyricsProvenance(it) }),
        type,
    )
}

/**
 * Files belong to a single recording, and an invalid replacement leaves the previous one intact.
 */
internal object SpicyImports {
    private val previews = android.util.LruCache<String, LyricsDocument>(12)

    private fun index(context: Context) =
        context.getSharedPreferences("ttml_library", Context.MODE_PRIVATE)

    fun library(context: Context): Map<String, String> =
        index(context).all.mapValues { it.value.toString() }

    private fun file(context: Context, track: String): AtomicFile {
        val name =
            MessageDigest.getInstance("SHA-256").digest(track.toByteArray()).joinToString("") {
                "%02x".format(it)
            }
        return AtomicFile(File(File(context.filesDir, "ttml"), name))
    }

    fun read(context: Context, track: String) =
        previews.get(track)
            ?: file(context, track).let { target ->
                if (!target.baseFile.exists()) null
                else target.openRead().use { TtmlLyricsParser.parse(it) }
            }

    fun remove(context: Context, track: String) {
        previews.remove(track)
        file(context, track).delete()
        index(context).edit().remove(track).apply()
    }

    fun discardPreview(track: String) = previews.remove(track) != null

    fun load(
        context: Context,
        track: String,
        uri: Uri,
        persist: Boolean,
        title: String,
    ): LyricsDocument {
        val bytes =
            (context.contentResolver.openInputStream(uri)
                    ?: throw java.io.IOException("Unreadable document"))
                .use { input ->
                    val out = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val size = input.read(buffer)
                        if (size < 0) break
                        require(out.size() + size <= 1024 * 1024)
                        out.write(buffer, 0, size)
                    }
                    out.toByteArray()
                }
        require(!bytes.toString(Charsets.UTF_8).contains("<!DOCTYPE", ignoreCase = true))
        val document = TtmlLyricsParser.parse(bytes.inputStream())
        require(document.lines.any { line -> line.words.any { it.text.isNotBlank() } })
        if (persist) {
            val target = file(context, track)
            target.baseFile.parentFile?.mkdirs()
            val stream = target.startWrite()
            try {
                stream.write(bytes)
                target.finishWrite(stream)
            } catch (e: Exception) {
                target.failWrite(stream)
                throw e
            }
            previews.remove(track)
            index(context).edit().putString(track, title).apply()
        } else previews.put(track, document)
        return document
    }
}
