package com.music.spotui.data.themes

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.music.spotui.di.Graph
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

object ThemeManager {
    private val storage by lazy { ThemeStorage(File(Graph.app.filesDir, "celestify-themes")) }
    var snapshot by mutableStateOf(ThemeSnapshot())
        private set
    var loadError by mutableStateOf<String?>(null)
        private set
    private val lock = Mutex()
    private var loaded = false
    suspend fun load() = lock.withLock {
        if (!loaded) {
            try { snapshot = withContext(Dispatchers.IO) { storage.read() } }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) { loadError = "Saved themes could not be read. Celestify defaults are active." }
            loaded = true
        }
    }
    private suspend fun change(transform: (ThemeSnapshot) -> ThemeSnapshot) = lock.withLock {
        val next = transform(snapshot)
        withContext(kotlinx.coroutines.NonCancellable) {
            withContext(Dispatchers.IO) { storage.write(next) }
            snapshot = next
            loadError = null
        }
    }
    suspend fun install(preview: ThemePreview, scheme: String) {
        require(preview.converted.compatibility != ThemeCompatibility.UNSUPPORTED)
        val candidate = preview.candidate
        val item = InstalledTheme(candidate.id, preview.name, preview.author, candidate.repository, candidate.path, candidate.revision, scheme,
            preview.converted.schemes.getValue(scheme), preview.converted.compatibility)
        change { old -> old.copy(installed = old.installed.filterNot { it.id == item.id } + item, applied = old.active) }
    }
    suspend fun activate(id: String) = change { old -> val item = old.installed.first { it.id == id }; old.copy(activeId = id, applied = item) }
    suspend fun reset() = change { it.copy(activeId = null, applied = null) }
    suspend fun remove(id: String) = change { old -> old.copy(installed = old.installed.filterNot { it.id == id }, activeId = old.activeId.takeUnless { it == id }, applied = old.applied.takeUnless { it?.id == id }) }
}
