package com.music.spotui.data.themes

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import org.json.JSONArray
import org.json.JSONObject

data class InstalledTheme(val id: String, val name: String, val author: String, val repository: String, val path: String, val revision: String,
    val scheme: String, val colors: NativeColors, val compatibility: ThemeCompatibility) {
    fun json() = JSONObject().put("id", id).put("name", name).put("author", author).put("repository", repository).put("path", path)
        .put("revision", revision).put("scheme", scheme).put("colors", colors.json()).put("compatibility", compatibility.name)
    companion object {
        fun read(o: JSONObject) = InstalledTheme(o.getString("id"), o.getString("name"), o.getString("author"), o.getString("repository"), o.getString("path"),
            o.getString("revision"), o.getString("scheme"), SpicetifyParser.normalize(NativeColors.read(o.getJSONObject("colors"))), ThemeCompatibility.valueOf(o.getString("compatibility")))
    }
}
data class ThemeSnapshot(val installed: List<InstalledTheme> = emptyList(), val activeId: String? = null, val applied: InstalledTheme? = null) {
    val active get() = applied ?: installed.firstOrNull { it.id == activeId }
}
/** One atomic registry contains both the installed configurations and active selection. */
class ThemeStorage(private val directory: File) {
    private val target get() = File(directory, "themes.json")
    fun read(): ThemeSnapshot {
        if (!target.exists()) return ThemeSnapshot()
        require(target.length() <= 1024 * 1024) { "Theme registry too large" }
        val obj = JSONObject(target.readText())
        val arr = obj.getJSONArray("installed")
        val installed = List(arr.length()) { InstalledTheme.read(arr.getJSONObject(it)) }
        val active = obj.optString("active").takeIf { id -> installed.any { it.id == id } }
        return ThemeSnapshot(installed, active, obj.optJSONObject("applied")?.let { InstalledTheme.read(it) }?.takeIf { it.id == active })
    }
    fun write(snapshot: ThemeSnapshot) {
        require(snapshot.installed.size <= 100) { "Theme limit reached" }
        directory.mkdirs()
        val text = JSONObject().put("installed", JSONArray(snapshot.installed.map { it.json() })).put("active", snapshot.activeId ?: "").put("applied", snapshot.applied?.json()).toString()
        require(text.toByteArray().size <= 1024 * 1024) { "Theme registry too large" }
        val temp = File(directory, "themes.tmp")
        try {
            java.io.FileOutputStream(temp).use { it.write(text.toByteArray()); it.fd.sync() }
            Files.move(temp.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally { temp.delete() }
    }
}
