package com.music.spotui.ui.immersive.pages

import android.content.Intent
import android.net.Uri
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.myspoti.engine.R
import com.music.spotui.data.themes.*
import com.music.spotui.ui.immersive.Immersive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CelestialThemesScreen(back: () -> Unit) {
    val context = LocalContext.current
    val resources = androidx.compose.ui.platform.LocalResources.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences("celestify-marketplace", 0) }
    var repo by rememberSaveable { mutableStateOf(prefs.getString("repository", "https://github.com/sanoojes/spicetify-glassify").orEmpty()) }
    var catalog by remember { mutableStateOf<List<ThemeCandidate>>(emptyList()) }
    val inspected = remember { mutableStateMapOf<String, ThemePreview>() }
    val previewSlots = remember { kotlinx.coroutines.sync.Semaphore(3) }
    var preview by remember { mutableStateOf<ThemePreview?>(null) }
    var scheme by rememberSaveable { mutableStateOf("") }
    var section by rememberSaveable { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var remove by remember { mutableStateOf<InstalledTheme?>(null) }
    val snapshot = ThemeManager.snapshot
    val catalogScroll = androidx.compose.foundation.lazy.rememberLazyListState()
    val previewScroll = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(preview?.candidate?.id) { previewScroll.scrollToItem(0) }
    fun work(label: String, action: suspend () -> Unit) {
        if (busy != null) return
        busy = label; error = null; notice = null
        scope.launch {
            try { action() } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: resources.getString(R.string.themes_error) }
            finally { busy = null }
        }
    }
    fun discover() = work(resources.getString(R.string.themes_loading)) {
        catalog = GitHubThemes.discover(repo)
        prefs.edit().putString("repository", "https://github.com/${GitHubThemes.repository(repo)}").apply()
        if (catalog.isEmpty()) notice = resources.getString(R.string.themes_no_supported_files)
    }
    fun open(candidate: ThemeCandidate) = work(resources.getString(R.string.themes_loading)) {
        val loaded = GitHubThemes.preview(candidate) { busy = it }
        preview = loaded; scheme = loaded.converted.schemes.keys.firstOrNull().orEmpty()
    }
    LaunchedEffect(Unit) { ThemeManager.load() }
    androidx.activity.compose.BackHandler { if (preview != null) preview = null else back() }
    ImmersivePage(title = stringResource(R.string.themes_title), onBack = { if (preview != null) preview = null else back() },
        modifier = Modifier.imePadding(), listState = if (preview == null) catalogScroll else previewScroll) {
        item {
            Column(Modifier.fillMaxWidth().padding(Immersive.Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.themes_intro), style = Immersive.Subhead)
                if (busy != null) {
                    LinearProgressIndicator(Modifier.fillMaxWidth(), color = Immersive.Accent)
                    Text(busy.orEmpty(), style = Immersive.Caption)
                }
                (error ?: ThemeManager.loadError)?.let { Text(it, color = MaterialTheme.colorScheme.error, style = Immersive.Body) }
                notice?.let { Text(it, style = Immersive.Subhead) }
                if (snapshot.active != null) TextButton(enabled = busy == null, onClick = { work(resources.getString(R.string.themes_saving)) {
                    ThemeManager.reset()
                    com.music.spotui.data.preferences.CelestialThemePref.set(context, com.music.spotui.data.preferences.CelestialTheme.ADAPTIVE)
                } }) { Text(stringResource(R.string.themes_reset)) }
            }
        }
        val selected = preview
        if (selected != null) {
            item {
                Column(Modifier.fillMaxWidth().padding(horizontal = Immersive.Gutter), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(selected.name, style = Immersive.Title)
                    Text(selected.author, style = Immersive.Subhead)
                    Text(selected.description, style = Immersive.Body)
                    Text(compatibilityLabel(selected.converted.compatibility), color = Immersive.Accent, style = Immersive.BodyStrong)
                    Text(stringResource(R.string.themes_compatibility_detail), style = Immersive.Caption)
                    ThemeEffectSummary(selected.converted.effects)
                    selected.converted.notices.distinct().forEach { Text("• $it", style = Immersive.Caption) }
                    val bitmap = remember(selected) {
                        selected.screenshot?.let { data ->
                            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
                            if (bounds.outWidth in 1..4096 && bounds.outHeight in 1..4096) {
                                val opts = BitmapFactory.Options().apply { inSampleSize = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 800) }
                                BitmapFactory.decodeByteArray(data, 0, data.size, opts)?.asImageBitmap()
                            } else null
                        }
                    }
                    if (bitmap != null) {
                        Text(stringResource(R.string.themes_desktop_preview), style = Immersive.Caption)
                        Image(bitmap, stringResource(R.string.themes_desktop_preview), Modifier.fillMaxWidth().heightIn(max = 220.dp).clip(Immersive.Card))
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        selected.converted.schemes.keys.forEach { key -> FilterChip(selected = scheme == key, onClick = { scheme = key }, label = { Text(key) }) }
                    }
                    selected.converted.schemes[scheme]?.let { colors ->
                        NativeThemePreview(colors)
                        Button(enabled = busy == null, onClick = { work(resources.getString(R.string.themes_saving)) {
                            ThemeManager.install(selected, scheme)
                            notice = resources.getString(R.string.themes_installed_message)
                        } }) { Text(stringResource(R.string.themes_install)) }
                        val installed = snapshot.installed.firstOrNull { it.id == selected.candidate.id && it.scheme == scheme && it.revision == selected.candidate.revision }
                        if (installed != null) Button(enabled = busy == null, onClick = { work(resources.getString(R.string.themes_saving)) { ThemeManager.activate(installed.id) } }) {
                            Text(stringResource(if (snapshot.active == installed) R.string.themes_active else R.string.themes_apply))
                        }
                    }
                    TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(selected.candidate.page))) }) { Text(stringResource(R.string.themes_repository)) }
                }
            }
        } else {
            item {
                Column(Modifier.padding(horizontal = Immersive.Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    ImmersiveSegmentedControl(listOf(stringResource(R.string.themes_discover), stringResource(R.string.themes_installed), stringResource(R.string.themes_updates)), section, { section = it }, Modifier.fillMaxWidth())
                    if (section == 0) {
                        OutlinedTextField(repo, { repo = it }, label = { Text(stringResource(R.string.themes_repository)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(enabled = busy == null, onClick = { discover() }) { Text(stringResource(R.string.themes_browse)) }
                            OutlinedButton(enabled = busy == null, onClick = {
                                repo = "https://github.com/sanoojes/spicetify-glassify"
                                discover()
                            }) { Text(stringResource(R.string.themes_glassify_featured)) }
                        }
                    }
                    if (section == 2) Button(enabled = busy == null, onClick = { work(resources.getString(R.string.themes_loading)) {
                        val found = mutableListOf<ThemeCandidate>()
                        snapshot.installed.map { it.repository }.distinct().forEach { found += GitHubThemes.discover(it) }
                        catalog = found
                        notice = resources.getString(R.string.themes_checked)
                    } }) { Text(stringResource(R.string.themes_check_updates)) }
                    if (section == 1 && snapshot.installed.isEmpty()) Text(stringResource(R.string.themes_empty), style = Immersive.Subhead)
                }
            }
            if (section == 0) items(catalog, key = { it.id }) { candidate ->
                val key = candidate.id + candidate.revision
                val ready = inspected[key]
                LaunchedEffect(key) {
                    if (ready == null) {
                        previewSlots.acquire()
                        try {
                            inspected[key] = GitHubThemes.preview(candidate, includeScreenshot = false)
                        } catch (e: CancellationException) { throw e }
                        catch (_: Exception) { /* Explicit Preview action retries and shows the network error. */ }
                        finally { previewSlots.release() }
                    }
                }
                ThemeCard(ready?.name ?: candidate.name, ready?.author ?: candidate.author, ready?.description ?: candidate.description,
                    if (snapshot.installed.any { it.id == candidate.id }) stringResource(R.string.themes_installed) else stringResource(R.string.themes_inspect),
                    busy == null, { open(candidate) }, ready)
            }
            if (section == 1) items(snapshot.installed, key = { it.id }) { installed ->
                Column(Modifier.padding(horizontal = Immersive.Gutter, vertical = 10.dp).clip(Immersive.Card).background(Immersive.Secondary).padding(16.dp)) {
                    Text(installed.name, style = Immersive.Headline)
                    Text("${installed.author} · ${installed.scheme}", style = Immersive.Subhead)
                    Text(compatibilityLabel(installed.compatibility), style = Immersive.Caption)
                    ThemeEffectSummary(installed.effects)
                    NativeThemePreview(installed.colors)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(enabled = busy == null, onClick = { work(resources.getString(R.string.themes_saving)) { ThemeManager.activate(installed.id) } }) { Text(stringResource(if (snapshot.active == installed) R.string.themes_active else R.string.themes_apply)) }
                        TextButton(enabled = busy == null, onClick = { remove = installed }) { Text(stringResource(R.string.themes_remove)) }
                    }
                }
            }
            if (section == 2) {
                val updates = catalog.filter { c -> snapshot.installed.any { it.id == c.id && it.revision != c.revision } }
                if (updates.isEmpty()) item { Text(stringResource(R.string.themes_no_updates), style = Immersive.Subhead, modifier = Modifier.padding(Immersive.Gutter)) }
                items(updates, key = { it.id }) { candidate -> ThemeCard(candidate.name, candidate.author, stringResource(R.string.themes_update_available), stringResource(R.string.themes_preview_update), busy == null, { open(candidate) }) }
            }
        }
    }
    remove?.let { target -> AlertDialog(onDismissRequest = { remove = null }, title = { Text(stringResource(R.string.themes_remove)) }, text = { Text(target.name) },
        confirmButton = { TextButton(onClick = { remove = null; work(resources.getString(R.string.themes_saving)) { ThemeManager.remove(target.id) } }) { Text(stringResource(R.string.themes_remove)) } },
        dismissButton = { TextButton(onClick = { remove = null }) { Text(stringResource(android.R.string.cancel)) } }) }
}

@Composable
private fun compatibilityLabel(value: ThemeCompatibility) = stringResource(when (value) {
    ThemeCompatibility.FULL -> R.string.themes_full
    ThemeCompatibility.PARTIAL -> R.string.themes_partial
    ThemeCompatibility.UNSUPPORTED -> R.string.themes_unsupported
})

@Composable
private fun ThemeEffectSummary(effects: NativeEffects) {
    if (effects.presentation != ThemePresentation.GLASSIFY) return
    Text(
        stringResource(R.string.themes_glassify_native),
        color = Immersive.Accent,
        style = Immersive.Caption,
    )
}

@Composable
private fun ThemeCard(name: String, author: String, description: String, action: String, enabled: Boolean, onClick: () -> Unit, preview: ThemePreview? = null) {
    Column(Modifier.fillMaxWidth().padding(horizontal = Immersive.Gutter, vertical = 8.dp).clip(Immersive.Card).background(Immersive.Secondary).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(name, style = Immersive.Headline)
        Text(author, style = Immersive.Subhead)
        Text(description, style = Immersive.Caption, maxLines = 3)
        preview?.let {
            Text(compatibilityLabel(it.converted.compatibility), style = Immersive.Caption, color = Immersive.Accent)
            ThemeEffectSummary(it.converted.effects)
            it.converted.schemes.values.firstOrNull()?.let { colors -> NativeThemePreview(colors) }
        }
        TextButton(enabled = enabled, onClick = onClick) { Text(action) }
    }
}

/** All colors are explicit: previewing never mutates the application's current palette. */
@Composable
private fun NativeThemePreview(c: NativeColors) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color(c.background)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.themes_native_preview), color = Color(c.text), fontSize = 20.sp)
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color(c.surface)).padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(8.dp)).background(Color(c.accent)))
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text("Celestify", color = Color(c.text))
                Text(stringResource(R.string.themes_preview_caption), color = Color(c.secondary), fontSize = 12.sp)
            }
            Text("▶", color = Color(c.accent), fontSize = 24.sp)
        }
        LinearProgressIndicator(progress = { .42f }, modifier = Modifier.fillMaxWidth(), color = Color(c.accent), trackColor = Color(c.elevated))
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(50)).background(Color(c.elevated).copy(alpha = .85f)).padding(12.dp), horizontalArrangement = Arrangement.SpaceAround) {
            Text("●", color = Color(c.accent)); Text("♫", color = Color(c.secondary)); Text("⌕", color = Color(c.secondary))
        }
    }
}
