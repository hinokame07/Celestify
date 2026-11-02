package com.music.spotui.data.themes

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.TimeUnit

data class ThemeCandidate(val repository: String, val path: String, val revision: String, val files: Set<String>, val description: String, val author: String) {
    val name get() = path.substringAfterLast('/').ifBlank { repository.substringAfter('/') }
    val id get() = "$repository/$path"
    val page get() = "https://github.com/$repository" + if (path.isBlank()) "" else "/tree/$revision/$path"
}
data class ThemePreview(val candidate: ThemeCandidate, val converted: ConvertedTheme, val name: String, val author: String, val description: String, val screenshot: ByteArray?)

object GitHubThemes {
    private val http = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()
    fun repository(input: String): String {
        val uri = URI(if (input.startsWith("https://")) input else "https://github.com/$input")
        require(uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null && uri.port == -1 && uri.query == null && uri.fragment == null) { "Use a public https://github.com/owner/repository URL" }
        val parts = uri.path.trim('/').removeSuffix(".git").split('/')
        require(parts.size == 2 && parts.all { it.matches(Regex("[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}")) && it != ".." }) { "Use the repository URL, without a branch or file path" }
        return parts.joinToString("/")
    }
    fun validPath(path: String): Boolean = path.isNotBlank() && path.length < 600 && !path.startsWith('/') && '\\' !in path && ':' !in path &&
        path.split('/').all { it.isNotEmpty() && it != "." && it != ".." && it.none { c -> c.code < 32 } }
    private fun get(url: String, limit: Int): ByteArray {
        val uri = URI(url)
        require(uri.scheme == "https" && uri.host in setOf("api.github.com", "raw.githubusercontent.com"))
        return http.newCall(Request.Builder().url(url).header("Accept", "application/vnd.github+json").header("User-Agent", "Celestify-Themes/1").build()).execute().use { r ->
            when (r.code) {
                403, 429 -> error("GitHub limit reached. Try again later.")
                404 -> error("Repository or theme not found. It must be public.")
            }
            check(r.isSuccessful) { "GitHub request failed (${r.code}). Try again." }
            val body = r.body
            require(body.contentLength() <= limit) { "Theme file is too large" }
            body.byteStream().use { stream ->
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) { val n = stream.read(buffer); if (n < 0) break; require(out.size() + n <= limit) { "Theme file is too large" }; out.write(buffer, 0, n) }
                out.toByteArray()
            }
        }
    }
    suspend fun discover(input: String): List<ThemeCandidate> = withContext(Dispatchers.IO) {
        val repo = repository(input)
        val metadata = JSONObject(String(get("https://api.github.com/repos/$repo", 512 * 1024)))
        val branch = metadata.getString("default_branch")
        val branchEncoded = java.net.URLEncoder.encode(branch, "UTF-8")
        val commit = JSONObject(String(get("https://api.github.com/repos/$repo/commits/$branchEncoded", 2 * 1024 * 1024))).getString("sha")
        require(commit.matches(Regex("[0-9a-f]{40}")))
        val tree = JSONObject(String(get("https://api.github.com/repos/$repo/git/trees/$commit?recursive=1", 6 * 1024 * 1024)))
        require(!tree.optBoolean("truncated")) { "Repository is too large to inspect safely" }
        val nodes = tree.getJSONArray("tree")
        val files = (0 until nodes.length()).map { nodes.getJSONObject(it) }.filter {
            it.optString("type") == "blob" && it.optString("mode") == "100644" && validPath(it.getString("path"))
        }.map { it.getString("path") }.toSet()
        val directories = files.filter { it.substringAfterLast('/') in setOf("color.ini", "user.css", "celestify.json") }.map { it.substringBeforeLast('/', "") }.distinct()
        require(directories.size <= 150) { "Too many themes in this repository" }
        directories.sorted().map { path -> ThemeCandidate(repo, path, commit, files.filter { path.isEmpty() || it.startsWith("$path/") }.toSet(),
            metadata.optString("description").takeUnless { it == "null" }.orEmpty().take(400), metadata.getJSONObject("owner").getString("login")) }
    }
    suspend fun preview(candidate: ThemeCandidate, includeScreenshot: Boolean = true, progress: (String) -> Unit = {}): ThemePreview = withContext(Dispatchers.IO) {
        fun raw(path: String, limit: Int): ByteArray {
            require(validPath(path) && candidate.revision.matches(Regex("[0-9a-f]{40}")))
            val encoded = path.split('/').joinToString("/") { java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
            return get("https://raw.githubusercontent.com/${repository(candidate.repository)}/${candidate.revision}/$encoded", limit)
        }
        fun file(name: String): String? = candidate.files.firstOrNull { it == listOf(candidate.path, name).filter { p -> p.isNotEmpty() }.joinToString("/") }?.let { String(raw(it, SpicetifyParser.MAX_TEXT), Charsets.UTF_8) }
        progress("Downloading colors…")
        val ini = file("color.ini")
        progress("Inspecting CSS…")
        val css = file("user.css")
        val native = file("celestify.json")
        val manifestText = file("manifest.json")
        val manifest = manifestText?.let { if (it.trimStart().startsWith('[')) org.json.JSONArray(it).optJSONObject(0) else JSONObject(it) }
        progress("Converting native preview…")
        val converted = GlassifyAdapter.adapt(candidate.repository, manifest, SpicetifyParser.parse(ini, css, native))
        val author = manifest?.optJSONArray("authors")?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.optString("name") }.joinToString(", ") }?.takeIf { it.isNotBlank() } ?: candidate.author
        // Only repository-owned raster previews; scripts, SVG and arbitrary external URLs are never loaded.
        val readme = if (includeScreenshot) file("README.md") ?: file("readme.md") else null
        val imageRefs = Regex("!\\[[^]]*]\\(([^ )]+)").findAll(readme.orEmpty()).map { it.groupValues[1] }.toList() +
            Regex("<img[^>]*src=[\"']([^\"']+)", RegexOption.IGNORE_CASE).findAll(readme.orEmpty()).map { it.groupValues[1] }.toList()
        val shot = imageRefs.map { listOf(candidate.path, it.removePrefix("./")).filter { p -> p.isNotEmpty() }.joinToString("/") }
            .firstOrNull { validPath(it) && it in candidate.files && it.substringAfterLast('.').lowercase() in setOf("png", "jpg", "jpeg", "webp") }
            ?: candidate.files.firstOrNull { it.substringAfterLast('/').lowercase().matches(Regex("(preview|screenshot|screenshot1)\\.(png|jpg|jpeg|webp)")) }
        val image = if (includeScreenshot) shot?.let { runCatching { raw(it, 2 * 1024 * 1024) }.getOrNull() } else null
        ThemePreview(candidate, converted, manifest?.optString("name")?.takeIf { it.isNotBlank() }?.take(100) ?: candidate.name,
            author.take(200), manifest?.optString("description")?.takeIf { it.isNotBlank() }?.take(500) ?: candidate.description, image)
    }
}
