package com.music.spotui.data.themes

import org.json.JSONObject
import kotlin.math.pow

enum class ThemeCompatibility { FULL, PARTIAL, UNSUPPORTED }
enum class ThemePresentation { STANDARD, GLASSIFY }

/** Native-only rendering hints. Remote CSS and JavaScript are never executed. */
data class NativeEffects(
    val presentation: ThemePresentation = ThemePresentation.STANDARD,
    val dynamicArtwork: Boolean = false,
    val glassOpacity: Float = .84f,
    val surfaceTint: Float = 0f,
    val preferLiquidGlass: Boolean = false,
) {
    fun json() = JSONObject()
        .put("presentation", presentation.name)
        .put("dynamicArtwork", dynamicArtwork)
        .put("glassOpacity", glassOpacity.toDouble())
        .put("surfaceTint", surfaceTint.toDouble())
        .put("preferLiquidGlass", preferLiquidGlass)

    companion object {
        fun read(o: JSONObject?) = if (o == null) NativeEffects() else NativeEffects(
            presentation = runCatching { ThemePresentation.valueOf(o.optString("presentation")) }.getOrDefault(ThemePresentation.STANDARD),
            dynamicArtwork = o.optBoolean("dynamicArtwork"),
            glassOpacity = o.optDouble("glassOpacity", .84).toFloat().coerceIn(.35f, .96f),
            surfaceTint = o.optDouble("surfaceTint", 0.0).toFloat().coerceIn(0f, .18f),
            preferLiquidGlass = o.optBoolean("preferLiquidGlass"),
        )

        val Glassify = NativeEffects(
            presentation = ThemePresentation.GLASSIFY,
            dynamicArtwork = true,
            glassOpacity = .70f,
            surfaceTint = .08f,
            preferLiquidGlass = true,
        )
    }
}
data class NativeColors(val background: Int, val surface: Int, val elevated: Int, val text: Int, val secondary: Int, val accent: Int) {
    fun json() = JSONObject().put("background", background).put("surface", surface).put("elevated", elevated)
        .put("text", text).put("secondary", secondary).put("accent", accent)
    companion object {
        fun read(o: JSONObject) = NativeColors(o.getInt("background"), o.getInt("surface"), o.getInt("elevated"), o.getInt("text"), o.getInt("secondary"), o.getInt("accent"))
    }
}
data class ConvertedTheme(
    val schemes: Map<String, NativeColors>,
    val compatibility: ThemeCompatibility,
    val notices: List<String>,
    val effects: NativeEffects = NativeEffects(),
)

/**
 * Android profile for sanoojes/spicetify-glassify (AGPL-3.0).
 *
 * Glassify's repository-level color.ini intentionally contains only `[dark]`; its appearance is
 * produced by a TypeScript extension and SCSS. Celestify does not execute that desktop code. It
 * recognizes the upstream repository and maps its documented/default artwork background, dark
 * glass, blur and floating-player intent onto Celestify's native renderer instead.
 */
object GlassifyAdapter {
    const val REPOSITORY = "sanoojes/spicetify-glassify"
    private val colors = NativeColors(
        background = 0xff000000.toInt(),
        surface = 0xff1c1c1e.toInt(),
        elevated = 0xff2c2c2e.toInt(),
        text = 0xfff5f5f7.toInt(),
        secondary = 0xffa1a1a6.toInt(),
        accent = 0xffff5c74.toInt(),
    )

    fun adapt(repository: String, manifest: JSONObject?, converted: ConvertedTheme): ConvertedTheme {
        if (repository.lowercase() != REPOSITORY) return converted
        val manifestName = manifest?.optString("name").orEmpty()
        require(manifestName.isBlank() || manifestName.equals("Glassify", ignoreCase = true)) { "Unexpected Glassify manifest" }
        return ConvertedTheme(
            schemes = if (converted.schemes.isEmpty()) mapOf("Glassify · Dynamic" to colors) else converted.schemes,
            compatibility = ThemeCompatibility.PARTIAL,
            notices = converted.notices + "Glassify is rendered natively with artwork colors, translucent surfaces and Liquid Glass. Desktop scripts are not executed.",
            effects = NativeEffects.Glassify,
        )
    }
}

/** Native conversion v1. CSS is inspected as text, never executed or rendered. */
object SpicetifyParser {
    const val MAX_TEXT = 512 * 1024
    fun color(raw: String): Int? {
        val value = raw.trim().removeSuffix(";").trim()
        val hex = value.removePrefix("#")
        if (hex.matches(Regex("[0-9a-fA-F]{6}"))) return (0xff000000L or hex.toLong(16)).toInt()
        if (hex.matches(Regex("[0-9a-fA-F]{3}"))) return color(hex.map { "$it$it" }.joinToString(""))
        val rgb = value.removePrefix("rgb(").removeSuffix(")").split(',').map { it.trim().toIntOrNull() }
        if (rgb.size == 3 && rgb.all { it != null && it in 0..255 }) return (0xff000000L or (rgb[0]!!.toLong() shl 16) or (rgb[1]!!.toLong() shl 8) or rgb[2]!!.toLong()).toInt()
        return null
    }
    fun luminance(c: Int): Double {
        fun channel(n: Int): Double { val v = n / 255.0; return if (v <= .04045) v / 12.92 else ((v + .055) / 1.055).pow(2.4) }
        return channel(c shr 16 and 255) * .2126 + channel(c shr 8 and 255) * .7152 + channel(c and 255) * .0722
    }
    fun contrast(a: Int, b: Int): Double = (maxOf(luminance(a), luminance(b)) + .05) / (minOf(luminance(a), luminance(b)) + .05)
    private fun dark(c: Int, fallback: Int) = if (luminance(c) <= .035) c or 0xff000000.toInt() else fallback
    fun normalize(c: NativeColors): NativeColors {
        val bg = dark(c.background, 0xff000000.toInt())
        val surface = dark(c.surface, 0xff1c1c1e.toInt())
        val elevated = dark(c.elevated, 0xff2c2c2e.toInt())
        val backgrounds = listOf(bg, surface, elevated)
        fun readable(value: Int, fallback: Int) = if (backgrounds.all { contrast(value, it) >= 4.5 }) value or 0xff000000.toInt() else fallback
        return NativeColors(bg, surface, elevated, readable(c.text, 0xfff5f5f7.toInt()), readable(c.secondary, 0xffa1a1a6.toInt()), readable(c.accent, 0xffff5c74.toInt()))
    }
    fun parse(ini: String?, css: String?, native: String? = null): ConvertedTheme {
        listOfNotNull(ini, css, native).forEach { require(it.toByteArray().size <= MAX_TEXT && !it.startsWith("PK\u0003\u0004") && '\u0000' !in it) { "Invalid theme text or archive. Only text theme files are supported." } }
        if (native != null) {
            val obj = JSONObject(native)
            require(obj.keys().asSequence().all { it in setOf("schema", "colors") } && obj.getInt("schema") == 1) { "Unsupported native theme manifest" }
            val values = obj.getJSONObject("colors")
            require(values.keys().asSequence().toSet() == setOf("background", "surface", "elevated", "text", "secondary", "accent")) { "Unsupported native properties" }
            fun c(key: String) = color(values.getString(key)) ?: error("Invalid color: $key")
            val original = NativeColors(c("background"), c("surface"), c("elevated"), c("text"), c("secondary"), c("accent"))
            val safe = normalize(original)
            val full = original == safe && css.isNullOrBlank()
            return ConvertedTheme(mapOf("Native" to safe), if (full) ThemeCompatibility.FULL else ThemeCompatibility.PARTIAL,
                if (full) emptyList() else listOf("Colors adapted for dark mode. Desktop CSS is not applied."))
        }
        val sections = linkedMapOf<String, MutableMap<String, Int>>()
        var section = "Default"
        ini.orEmpty().lineSequence().forEach { raw ->
            val line = raw.trim().removePrefix("\uFEFF")
            if (line.startsWith('[') && line.endsWith(']')) { section = line.drop(1).dropLast(1).take(100); require(sections.size < 80) { "Too many color schemes" } }
            else if (!line.startsWith(';') && !line.startsWith('#') && '=' in line) {
                val key = line.substringBefore('=').trim().lowercase()
                color(line.substringAfter('=').substringBefore(';'))?.let { sections.getOrPut(section) { linkedMapOf() }[key] = it }
            }
        }
        val cssColors = linkedMapOf<String, Int>()
        Regex("--spice-([a-z-]+)\\s*:\\s*([^;}]+)").findAll(css.orEmpty()).forEach { m -> color(m.groupValues[2])?.let { cssColors[m.groupValues[1]] = it } }
        if (sections.isEmpty() && cssColors.isNotEmpty()) sections["CSS colors"] = cssColors
        val schemes = sections.filterValues { "main" in it && ("button" in it || "text" in it) }.mapValues { (_, p) ->
            normalize(NativeColors(p.getValue("main"), p["sidebar"] ?: p.getValue("main"), p["card"] ?: p["player"] ?: p.getValue("main"),
                p["text"] ?: 0xfff5f5f7.toInt(), p["subtext"] ?: 0xffa1a1a6.toInt(), p["button-active"] ?: p["button"] ?: p["accent"] ?: 0xffff5c74.toInt()))
        }
        return ConvertedTheme(schemes, if (schemes.isEmpty()) ThemeCompatibility.UNSUPPORTED else ThemeCompatibility.PARTIAL,
            listOf("Native color conversion only. Desktop selectors, layouts, fonts, animations and scripts are not applied. Light colors may be adapted for dark mode."))
    }
}
