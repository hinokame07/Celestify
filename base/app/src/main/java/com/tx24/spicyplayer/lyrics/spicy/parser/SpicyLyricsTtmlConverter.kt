// SPDX-License-Identifier: AGPL-3.0-only
// From spicylyrics/mobile at 4565dde58003a7796c2be32f3022cef773dfa73b.
package com.tx24.spicyplayer.lyrics.spicy.parser

import com.google.gson.JsonObject
import com.google.gson.JsonArray

object SpicyLyricsTtmlConverter {
    fun convert(body: JsonObject, content: JsonArray): String? {
        val defaultAgent = content.mapNotNull { it.takeIf { value -> value.isJsonObject }?.asJsonObject }
            .firstNotNullOfOrNull { it.string("Agent") ?: it.getAsJsonObject("Lead")?.string("Agent") }
        val transliterations = StringBuilder()
        var wordTimed = false
        val paragraphs = buildList {
            content.forEach { element ->
                val item = element.takeIf { it.isJsonObject }?.asJsonObject ?: return@forEach
                if (item.string("Type").equals("Interlude", ignoreCase = true)) return@forEach
                val lead = item.getAsJsonObject("Lead")
                val agent = item.string("Agent") ?: lead?.string("Agent")
                val opposite = item.get("OppositeAligned")?.takeIf { it.isJsonPrimitive }?.asBoolean
                    ?: (agent != null && defaultAgent != null && agent != defaultAgent)
                val key = "L${size + 1}"
                if (lead == null) {
                    // Line-type responses carry the text and timing on the item itself.
                    lineParagraph(key, item, agent, opposite)?.let(::add)
                    return@forEach
                }
                wordTimed = true
                paragraph(key, item, lead, item.getAsJsonArray("Background"), agent, opposite)?.let(::add) ?: return@forEach
                transliteration(lead.getAsJsonArray("Syllables"), item.getAsJsonArray("Background"))?.let {
                    transliterations.append("<text for=\"$key\">$it</text>")
                }
            }
        }
        if (paragraphs.isEmpty()) return null
        val writers = body.getAsJsonArray("SongWriters")
            ?.mapNotNull { it.takeIf { value -> value.isJsonPrimitive }?.asString }
            .orEmpty()
            .joinToString("") { "<songwriter>${xml(it)}</songwriter>" }
        return """<?xml version="1.0" encoding="UTF-8"?><tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" xmlns:spicy="https://spicylyrics.org/ns/ttml" itunes:timing="${if (wordTimed) "Word" else "Line"}"><head><metadata><iTunesMetadata xmlns="http://music.apple.com/lyric-ttml-internal"><songwriters>$writers</songwriters>${if (transliterations.isEmpty()) "" else "<transliterations><transliteration>$transliterations</transliteration></transliterations>"}</iTunesMetadata></metadata></head><body><div>${paragraphs.joinToString("")}</div></body></tt>"""
    }

    /** The API's per-syllable romanization as Apple-style spans; the parser matches them to syllables by timing. */
    private fun transliteration(lead: JsonArray?, backgrounds: JsonArray?): String? {
        fun romanSpans(syllables: JsonArray?) = syllables?.mapNotNull { element ->
            val syllable = element.takeIf { it.isJsonObject }?.asJsonObject ?: return@mapNotNull null
            val roman = syllable.string("TransliteratedText")?.trim()?.takeIf(String::isNotEmpty) ?: return@mapNotNull null
            val start = syllable.number("StartTime") ?: return@mapNotNull null
            val end = syllable.number("EndTime") ?: return@mapNotNull null
            "<span begin=\"${seconds(start)}\" end=\"${seconds(end)}\">${xml(roman)}</span>"
        }.orEmpty()
        val leadSpans = romanSpans(lead).joinToString("")
        val bgSpans = backgrounds?.mapNotNull { it.takeIf { value -> value.isJsonObject }?.asJsonObject }.orEmpty()
            .flatMap { romanSpans(it.getAsJsonArray("Syllables")) }.joinToString("")
        val all = leadSpans + if (bgSpans.isEmpty()) "" else "<span ttm:role=\"x-bg\">$bgSpans</span>"
        return all.ifEmpty { null }
    }

    private fun lineParagraph(key: String, item: JsonObject, agent: String?, opposite: Boolean): String? {
        val text = item.string("Text")?.takeIf(String::isNotBlank) ?: return null
        val start = item.number("StartTime") ?: return null
        val end = item.number("EndTime") ?: return null
        val agentAttribute = agent?.let { " ttm:agent=\"${xml(it)}\"" }.orEmpty()
        return "<p begin=\"${seconds(start)}\" end=\"${seconds(end)}\" itunes:key=\"$key\"$agentAttribute spicy:oppositeAligned=\"$opposite\">${xml(text)}${translationSpan(item)}</p>"
    }

    /** Untimed lyrics, each line with its translation if it has one. */
    fun static(lines: List<Pair<String, String?>>): String? {
        val paragraphs = lines.filter { it.first.isNotBlank() }.joinToString("") { (text, translation) ->
            "<p>${xml(text)}${translation?.trim()?.takeIf(String::isNotEmpty)?.let { "<span ttm:role=\"x-translation\">${xml(it)}</span>" }.orEmpty()}</p>"
        }.ifEmpty { return null }
        return """<?xml version="1.0" encoding="UTF-8"?><tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="None"><body><div>$paragraphs</div></body></tt>"""
    }

    /** The API's translation of a line or background group, as an inline x-translation span. */
    private fun translationSpan(vararg sources: JsonObject?): String = sources.firstNotNullOfOrNull { source ->
        source?.string("TranslatedText")?.trim()?.takeIf(String::isNotEmpty)
    }?.let { "<span ttm:role=\"x-translation\">${xml(it)}</span>" }.orEmpty()

    private fun paragraph(key: String, item: JsonObject, lead: JsonObject, backgrounds: JsonArray?, agent: String?, opposite: Boolean): String? {
        val leadSpans = spans(lead.getAsJsonArray("Syllables"))
        val bgGroups = backgrounds?.mapNotNull { element ->
            val group = element.takeIf { it.isJsonObject }?.asJsonObject ?: return@mapNotNull null
            spans(group.getAsJsonArray("Syllables")).takeIf(List<TimedText>::isNotEmpty)?.let { it to group }
        }.orEmpty()
        // A line is dropped only when its lead and every background group
        // are empty: a line can be background vocals alone (Industry Baby opens with one).
        if (leadSpans.isEmpty() && bgGroups.isEmpty()) return null
        val all = leadSpans + bgGroups.flatMap { it.first }
        val start = lead.number("StartTime") ?: all.minOf { it.start }
        val end = lead.number("EndTime") ?: all.maxOf { it.end }
        val bg = bgGroups.joinToString("") { (syllables, group) ->
            val singer = group.string("Agent")?.let { " ttm:agent=\"${xml(it)}\"" }.orEmpty()
            val side = group.get("OppositeAligned")?.takeIf { it.isJsonPrimitive }?.asBoolean
                ?.let { " spicy:oppositeAligned=\"$it\"" }.orEmpty()
            "<span ttm:role=\"x-bg\"$singer$side>${syllables.joinToString("") { it.xmlSpan() }}${translationSpan(group)}</span>"
        }
        val agentAttribute = agent?.let { " ttm:agent=\"${xml(it)}\"" }.orEmpty()
        return "<p begin=\"${seconds(start)}\" end=\"${seconds(end)}\" itunes:key=\"$key\"$agentAttribute spicy:oppositeAligned=\"$opposite\">${leadSpans.joinToString("") { it.xmlSpan() }}$bg${translationSpan(lead, item)}</p>"
    }

    private fun spans(array: JsonArray?): List<TimedText> = array?.mapIndexedNotNull { index, element ->
        val word = element.takeIf { it.isJsonObject }?.asJsonObject ?: return@mapIndexedNotNull null
        val text = word.string("Text") ?: return@mapIndexedNotNull null
        val start = word.number("StartTime") ?: return@mapIndexedNotNull null
        val end = word.number("EndTime") ?: return@mapIndexedNotNull null
        // Spicy marks whether this syllable joins the NEXT one, while TTML
        // spacing is expressed before the current span.
        val attached = index > 0 && array[index - 1].takeIf { it.isJsonObject }
            ?.asJsonObject?.get("IsPartOfWord")?.asBoolean == true
        TimedText(text, start, end, attached)
    }.orEmpty()

    private data class TimedText(val text: String, val start: Double, val end: Double, val attached: Boolean) {
        fun xmlSpan(): String = "<span begin=\"${seconds(start)}\" end=\"${seconds(end)}\">${if (!attached) " " else ""}${xml(text)}</span>"
    }

    private fun JsonObject.string(name: String): String? = get(name)?.takeIf { it.isJsonPrimitive }?.asString
    private fun JsonObject.number(name: String): Double? = get(name)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isNumber }?.asDouble
    private fun seconds(value: Double) = "${"%.3f".format(java.util.Locale.ROOT, value)}s"
    private fun xml(value: String) = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")
}

