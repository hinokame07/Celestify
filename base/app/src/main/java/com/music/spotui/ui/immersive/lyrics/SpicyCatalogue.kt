package com.music.spotui.ui.immersive.lyrics

import androidx.compose.runtime.*
import com.google.gson.JsonParser
import com.music.spotui.di.Graph
import com.tx24.spicyplayer.lyrics.spicy.models.*
import com.tx24.spicyplayer.lyrics.spicy.parser.SpicyLyricsTtmlConverter
import com.tx24.spicyplayer.lyrics.spicy.parser.TtmlLyricsParser
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Opt-in hosted catalogue. Only a publishable client key and the exact Spotify ID leave the device.
 */
internal object SpicyCatalogue {
    private val prefs
        get() = Graph.app.getSharedPreferences("spicy_stage", 0)

    var key by mutableStateOf(prefs.getString("client_key", "").orEmpty())
        private set

    fun valid(value: String) = value.isEmpty() || value.matches(Regex("sl_pk_[A-Za-z0-9_-]+"))

    fun save(value: String) {
        require(valid(value))
        key = value
        prefs.edit().putString("client_key", value).apply()
        cache.evictAll()
    }

    private val cache = android.util.LruCache<String, LyricsDocument>(12)

    fun forget(id: String? = null) {
        if (id == null) cache.evictAll() else cache.remove(id)
    }

    @Volatile private var retryAfter = 0L
    private val client =
        OkHttpClient.Builder()
            .followRedirects(false)
            .callTimeout(8, TimeUnit.SECONDS)
            .addInterceptor(com.music.spotui.data.DataSaver.interceptor)
            .build()

    fun lookup(id: String, clientKey: String, reload: Boolean): LyricsDocument? {
        if (clientKey.isBlank() || !id.matches(Regex("[A-Za-z0-9]{22}"))) return null
        if (!reload)
            cache.get(id)?.let {
                return it
            }
        if (System.currentTimeMillis() < retryAfter) return null
        val request =
            Request.Builder()
                .url("https://api.spicylyrics.org/v1/lyrics/$id")
                .header("Authorization", "Bearer $clientKey")
                .build()
        return client.newCall(request).execute().use { response ->
            if (response.code == 429) {
                val seconds =
                    response.header("Retry-After")?.toLongOrNull()?.coerceIn(1, 86400) ?: 60L
                retryAfter = System.currentTimeMillis() + seconds * 1000
            }
            if (!response.isSuccessful || response.body.source().request(2L * 1024 * 1024 + 1))
                return@use null
            val json = JsonParser.parseString(response.body.string()).asJsonObject
            if (json.get("Status")?.asInt != 200) return@use null
            val body = json.getAsJsonObject("Body") ?: return@use null
            val ttml =
                body.getAsJsonArray("Content")?.let { SpicyLyricsTtmlConverter.convert(body, it) }
                    ?: body.getAsJsonArray("Lines")?.let { array ->
                        SpicyLyricsTtmlConverter.static(
                            array.map {
                                val line = it.asJsonObject
                                line.get("Text")?.asString.orEmpty() to
                                    line
                                        .get("TranslatedText")
                                        ?.takeIf { v -> v.isJsonPrimitive }
                                        ?.asString
                            }
                        )
                    }
                    ?: return@use null
            val doc = TtmlLyricsParser.parse(ttml.byteInputStream())
            val upload = body.getAsJsonObject("UploadAttribution")
            fun credit(field: String): LyricsCredit? {
                val value = upload?.get(field) ?: return null
                val name =
                    if (value.isJsonPrimitive) value.asString
                    else if (value.isJsonObject)
                        listOf("Username", "username", "name", "Name").firstNotNullOfOrNull {
                            value.asJsonObject.get(it)?.takeIf { v -> v.isJsonPrimitive }?.asString
                        }
                    else null
                return name?.takeIf { it.isNotBlank() }?.let { LyricsCredit(it) }
            }
            doc.takeIf { it.lines.isNotEmpty() }
                ?.copy(
                    footer =
                        doc.footer.copy(
                            provenance =
                                LyricsProvenance(
                                    "Spicy Lyrics",
                                    body.get("source")?.takeIf { it.isJsonPrimitive }?.asString,
                                ),
                            maker = credit("Maker"),
                            uploader = credit("Uploader"),
                        )
                )
                ?.also { if (key == clientKey) cache.put(id, it) }
        }
    }
}
