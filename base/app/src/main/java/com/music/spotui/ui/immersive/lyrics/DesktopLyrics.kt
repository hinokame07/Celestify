package com.music.spotui.ui.immersive.lyrics

import com.tx24.spicyplayer.lyrics.spicy.models.*
import org.json.JSONArray
import org.json.JSONObject

/**
 * Convert milliseconds to the desktop Applyer's seconds. Android's join points to the previous
 * syllable; Spicy's IsPartOfWord points to the next syllable of the same word.
 */
internal fun desktopLyrics(lines: List<Line>, doc: LyricsDocument): JSONObject {
    fun group(line: Line) =
        JSONObject()
            .put("StartTime", line.startMs / 1000.0)
            .put("translation", line.translation)
            .put("EndTime", line.endMs / 1000.0)
            .put(
                "Syllables",
                JSONArray(
                    line.words.mapIndexed { i, word ->
                        JSONObject()
                            .put("Text", word.text)
                            .put("StartTime", word.startMs / 1000.0)
                            .put("EndTime", word.endMs / 1000.0)
                            .put("TransliteratedText", word.romanizedText)
                            .put("IsPartOfWord", line.words.getOrNull(i + 1)?.isPartOfWord == true)
                    }
                ),
            )
    val leads = lines.filter { it.role == LineRole.LEAD }
    val backing = lines.filter { it.isBackground && it.groupId != null }.groupBy { it.groupId }
    val syllables = doc.type == LyricsType.Syllable
    return JSONObject()
        .put("Type", if (syllables) "Syllable" else "Line")
        .put("StartTime", (leads.firstOrNull()?.words?.firstOrNull()?.startMs ?: 0) / 1000.0)
        .put(
            "credits",
            JSONArray(
                doc.footer.lines().map {
                    JSONObject()
                        .put("kind", it.kind.name)
                        .put("text", it.text)
                        .put("label", it.label)
                        .put("name", it.name)
                        .put("profile", it.profileUrl)
                }
            ),
        )
        .put(
            "Content",
            JSONArray(
                leads.map { line ->
                    val row =
                        JSONObject()
                            .put("OppositeAligned", line.oppositeAligned)
                            .put("translation", line.translation)
                    if (syllables)
                        row.put("Lead", group(line))
                            .put(
                                "Background",
                                JSONArray(backing[line.groupId].orEmpty().map(::group)),
                            )
                    else
                        row.put("Text", spicyStaticLineText(line, false))
                            .put("TransliteratedText", spicyStaticLineText(line, true))
                            .put("StartTime", line.startMs / 1000.0)
                            .put("EndTime", line.endMs / 1000.0)
                }
            ),
        )
}
