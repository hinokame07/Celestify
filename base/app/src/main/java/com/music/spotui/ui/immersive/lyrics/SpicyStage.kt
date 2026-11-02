package com.music.spotui.ui.immersive.lyrics

import android.content.Context
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.myspoti.engine.R
import com.music.spotui.data.entity.LyricTiming
import com.music.spotui.data.preferences.AtmospherePref
import com.music.spotui.di.SongPlayer
import com.music.spotui.ui.components.CelestifyMenu
import com.music.spotui.ui.immersive.Immersive
import com.music.spotui.ui.look.rememberReduceMotion
import com.music.spotui.ui.viewmodel.LyricsViewModel
import com.tx24.spicyplayer.lyrics.spicy.RenderConfig
import com.tx24.spicyplayer.lyrics.spicy.ScrollConfig
import com.tx24.spicyplayer.lyrics.spicy.canvas.LyricsView
import com.tx24.spicyplayer.lyrics.spicy.canvas.LyricsViewState
import com.tx24.spicyplayer.lyrics.spicy.models.*
import com.tx24.spicyplayer.lyrics.spicy.romanization.RomanizationMode
import com.tx24.spicyplayer.translation.TranslationMode
import com.tx24.spicyplayer.translation.TranslationPresentation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal enum class StageStyle {
    Spicy,
    Simple,
    Refreshed,
    Minimal,
    Apple,
    Celestify,
}

internal enum class StageBackground {
    Dynamic,
    Artist,
    Cover,
    Color,
    None,
}

internal enum class StageOption(val label: Int, val initial: Boolean) {
    Smooth(R.string.spicy_smooth, true),
    Lead(R.string.spicy_lead, false),
    SeekFade(R.string.spicy_seek_fade, false),
    Duets(R.string.spicy_duets, true),
    BackgroundVocals(R.string.spicy_backing, true),
    JoinWords(R.string.spicy_join, false),
    Credits(R.string.spicy_credits, true),
    MotionBackground(R.string.spicy_motion_bg, true),
    SystemFont(R.string.spicy_system_font, false),
    LimitFrames(R.string.spicy_limit_frames, false),
    HideNotice(R.string.spicy_hide_notice, false),
    Timeline(R.string.spicy_timeline, true),
    Volume(R.string.cinema_volume, true),
    LockedCover(R.string.spicy_lock_cover, false),
    Hover(R.string.spicy_hover, true),
    Canvas(R.string.spicy_canvas, true),
    GlassSlider(R.string.spicy_glass_slider, true),
    RefinedColors(R.string.spicy_refined_colors, true),
    ScrubPreview(R.string.spicy_scrub_preview, true),
    Skeleton(R.string.spicy_skeleton, true),
    Popup(R.string.spicy_floating, true),
    PopupDock(R.string.spicy_popup_dock, true),
    Overlap(R.string.spicy_overlap, true),
    RefinedCredits(R.string.spicy_refined_credits, true),
    BottomControls(R.string.spicy_bottom_controls, false),
    Diagnostics(R.string.spicy_diagnostics, false),
    ProviderFirst(R.string.spicy_provider_first, false),
}

internal object StagePreference {
    private val prefs
        get() =
            com.music.spotui.di.Graph.app.getSharedPreferences("spicy_stage", Context.MODE_PRIVATE)

    var style by
        mutableStateOf(
            StageStyle.entries.firstOrNull { it.name == prefs.getString("style", null) }
                ?: StageStyle.Spicy
        )
        private set

    private val options =
        mutableStateMapOf<StageOption, Boolean>().apply {
            StageOption.entries.forEach { put(it, prefs.getBoolean(it.name, it.initial)) }
        }

    operator fun get(option: StageOption) = options[option] ?: option.initial

    fun set(option: StageOption, value: Boolean) {
        options[option] = value
        prefs.edit().putBoolean(option.name, value).apply()
    }

    fun select(value: StageStyle) {
        style = value
        prefs.edit().putString("style", value.name).apply()
    }

    var background by
        mutableStateOf(
            StageBackground.entries.firstOrNull { it.name == prefs.getString("background", null) }
                ?: StageBackground.Dynamic
        )
        private set

    var blur by mutableIntStateOf(prefs.getInt("background_blur", 0))
        private set

    var fps by
        mutableIntStateOf(prefs.getInt("frame_rate", if (get(StageOption.LimitFrames)) 30 else 60))
        private set

    fun background(value: StageBackground) {
        background = value
        prefs.edit().putString("background", value.name).apply()
    }

    fun blur(value: Int) {
        blur = value.coerceIn(0, 64)
        prefs.edit().putInt("background_blur", blur).apply()
    }

    fun fps(value: Int) {
        fps = value.coerceIn(15, 120)
        prefs.edit().putInt("frame_rate", fps).apply()
    }

    var leadMs by mutableIntStateOf(prefs.getInt("scroll_lead_ms", 250))
        private set

    fun setLead(value: Int) {
        leadMs = value.coerceIn(0, 800)
        prefs.edit().putInt("scroll_lead_ms", leadMs).apply()
    }
}

@Composable
internal fun SpicyStage(
    track: String,
    state: LyricsViewModel.State,
    vm: LyricsViewModel,
    modifier: Modifier,
    inset: PaddingValues,
    cinemaState: MutableState<Boolean>,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences("spicy_stage", Context.MODE_PRIVATE) }
    val trackTitle =
        com.music.spotui.di.Graph.currentSongState.title.value +
            " · " +
            com.music.spotui.di.Graph.currentSongState.singer.value
    val source = (state as? LyricsViewModel.State.Loaded)?.lyrics
    val duration = SongPlayer.getDuration()
    val online by
        produceState<LyricsDocument?>(null, source, duration) {
            value = source?.let { withContext(Dispatchers.Default) { it.spicyDocument(duration) } }
        }
    var local by remember(track) { mutableStateOf<LyricsDocument?>(null) }
    var revision by remember(track) { mutableIntStateOf(0) }
    LaunchedEffect(track, revision) {
        if (revision == 0)
            local =
                withContext(Dispatchers.IO) {
                    runCatching { SpicyImports.read(context, track) }.getOrNull()
                }
    }
    var persist by rememberSaveable { mutableStateOf(true) }
    var importTrack by rememberSaveable { mutableStateOf("") }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null && importTrack == track)
                scope.launch {
                    try {
                        val doc =
                            withContext(Dispatchers.IO) {
                                SpicyImports.load(context, track, uri, persist, trackTitle)
                            }
                        revision++
                        local = doc
                    } catch (_: java.io.IOException) {
                        Toast.makeText(context, R.string.spicy_import_error, Toast.LENGTH_LONG)
                            .show()
                    } catch (_: IllegalArgumentException) {
                        Toast.makeText(context, R.string.spicy_import_error, Toast.LENGTH_LONG)
                            .show()
                    } catch (_: SecurityException) {
                        Toast.makeText(context, R.string.spicy_import_error, Toast.LENGTH_LONG)
                            .show()
                    }
                }
        }
    var reload by remember(track) { mutableIntStateOf(0) }
    val catalogueKey = SpicyCatalogue.key
    val hosted by
        produceState<LyricsDocument?>(null, track, catalogueKey, reload) {
            value = null
            value =
                withContext(Dispatchers.IO) {
                    runCatching { SpicyCatalogue.lookup(track, catalogueKey, reload > 0) }
                        .getOrNull()
                }
        }
    val doc =
        local
            ?: if (StagePreference[StageOption.ProviderFirst]) online ?: hosted
            else hosted ?: online
    val systemFont = StagePreference[StageOption.SystemFont]
    LaunchedEffect(systemFont) {
        com.tx24.spicyplayer.lyrics.spicy.canvas.LyricsLayoutCalculator.setFont(
            if (systemFont) androidx.compose.ui.text.font.FontFamily.SansSerif else null,
            if (systemFont) "system" else "",
        )
    }
    val floating = LocalFloatingLyrics.current
    var romanize by remember { mutableStateOf(prefs.getBoolean("romanize", false)) }
    var scale by remember { mutableFloatStateOf(prefs.getFloat("size", 1f)) }
    var cinema by cinemaState
    var lyricsOnLeft by rememberSaveable {
        mutableStateOf(prefs.getBoolean("cinema_lyrics_left", false))
    }
    var menu by remember { mutableStateOf(false) }
    val reduced = rememberReduceMotion()
    val style = StagePreference.style
    val config =
        RenderConfig(
            simpleLyricsMode =
                style == StageStyle.Refreshed || style == StageStyle.Simple || reduced,
            minimalLyricsMode = style == StageStyle.Minimal,
            appleMusic = style == StageStyle.Apple && !reduced,
            refreshedSimple = style == StageStyle.Refreshed && !reduced,
            glowEnabled = AtmospherePref.lyricsGlow && !reduced,
            lettersEnabled = !reduced,
            distanceBlurEnabled = !reduced,
            wordMotionBoost = if (reduced) 0f else 1f,
            backgroundPop = StagePreference[StageOption.BackgroundVocals],
            wideDuetPadding = StagePreference[StageOption.Duets],
            creditsFollowLastLine = StagePreference[StageOption.Credits],
            syllableMerge =
                if (StagePreference[StageOption.JoinWords])
                    com.tx24.spicyplayer.lyrics.spicy.SyllableMerge.Steady
                else com.tx24.spicyplayer.lyrics.spicy.SyllableMerge.Off,
            scroll =
                ScrollConfig(
                    smooth = !reduced && StagePreference[StageOption.Smooth],
                    leadMs =
                        if (StagePreference[StageOption.Lead]) StagePreference.leadMs.toLong()
                        else 0L,
                    seekFadeCompensation = StagePreference[StageOption.SeekFade],
                ),
        )
    val translations =
        (state as? LyricsViewModel.State.Loaded)
            ?.takeIf { it.showTranslation && doc === online }
            ?.translations
    val lines by
        produceState<List<Line>>(
            emptyList(),
            doc,
            romanize,
            config.minimalLyricsMode,
            translations,
        ) {
            value =
                withContext(Dispatchers.Default) {
                    val original =
                        doc?.lines.orEmpty().mapIndexed { i, line ->
                            line.copy(translation = line.translation ?: translations?.getOrNull(i))
                        }
                    val converted =
                        if (!romanize) original
                        else {
                            val transliterator =
                                android.icu.text.Transliterator.getInstance("Any-Latin")
                            original.map { line ->
                                line.copy(
                                    words =
                                        line.words.map { word ->
                                            if (word.romanizedText != null) word
                                            else
                                                word.copy(
                                                    romanizedText =
                                                        transliterator
                                                            .transliterate(word.text)
                                                            .takeIf { it != word.text }
                                                )
                                        }
                                )
                            }
                        }
                    if (doc?.type == LyricsType.Static || converted.any { it.isInterlude })
                        converted
                    else buildDisplayTimeline(converted, config.minimalLyricsMode)
                }
        }
    val presentation =
        remember(lines) {
            val texts = lines.map { it.translation }
            if (texts.any { !it.isNullOrBlank() })
                TranslationPresentation(texts, TranslationMode.UnderLine)
            else null
        }
    val view = remember(track, doc) { LyricsViewState() }
    // Keep the alternatives that carry a native-only presentation (under-line translations,
    // individual untimed lines within a synced document, Apple style and accessibility).
    val useDesktop =
        !reduced &&
            style != StageStyle.Apple &&
            doc != null &&
            doc.type != LyricsType.Static &&
            lines.none { it.untimed || (doc.type == LyricsType.Syllable && it.lineTimed) }
    val document by
        key(track, doc, lines, useDesktop) {
            produceState<String?>(null) {
                if (useDesktop && doc != null && lines.isNotEmpty())
                    value =
                        withContext(Dispatchers.Default) { desktopLyrics(lines, doc).toString() }
            }
        }
    val playing = com.music.spotui.di.Graph.currentSongState.playingState.value
    var showDiagnostics by remember { mutableStateOf(false) }
    if (showDiagnostics)
        AlertDialog(
            onDismissRequest = { showDiagnostics = false },
            title = { Text(stringResource(R.string.spicy_diagnostics)) },
            text = {
                Text(
                    listOf(
                            track,
                            doc?.footer?.provenance?.provider.orEmpty(),
                            doc?.type?.name.orEmpty(),
                            if (document != null) "Spicy Lyrics Desktop"
                            else "Spicy Lyrics Android",
                            "t = ${SongPlayer.getCurrentPosition()} / ${SongPlayer.getDuration()} ms",
                            "Δ = ${AtmospherePref.lyricsOffsetMs} ms",
                        )
                        .filter(String::isNotBlank)
                        .joinToString("\n")
                )
            },
            confirmButton = {
                TextButton({ showDiagnostics = false }) {
                    Text(stringResource(android.R.string.ok))
                }
            },
        )
    val lyricsBody: @Composable (Modifier) -> Unit = { frame ->
        Box(frame) {
            if (doc != null && lines.isNotEmpty()) {
                if (doc.type == LyricsType.Static) {
                    SpicyStaticLyrics(
                        lines,
                        doc.footer.lines(),
                        romanize,
                        if (floating) scale * .65f else scale,
                        Modifier.fillMaxSize(),
                    )
                } else
                    LyricsView(
                        lines,
                        track,
                        footer = doc.footer,
                        currentTimeMs = {
                            LyricTiming.position(
                                SongPlayer.getCurrentPosition(),
                                com.music.spotui.di.OutputLag.ms(),
                                AtmospherePref.lyricsOffsetMs,
                            )
                        },
                        onSeekWord = {
                            SongPlayer.seekTo(
                                LyricTiming.seekPosition(it, AtmospherePref.lyricsOffsetMs)
                            )
                            SongPlayer.play()
                        },
                        modifier = Modifier.fillMaxSize(),
                        config = config,
                        fontSizeScale = if (floating) scale * 0.65f else scale,
                        lyricsType = doc.type,
                        romanize = romanize,
                        romanizationMode = RomanizationMode.UnderLine,
                        translation = presentation,
                        isPlaying = playing,
                        viewState = view,
                        frameCap =
                            if (reduced) 30
                            else if (StagePreference[StageOption.LimitFrames]) StagePreference.fps
                            else 0,
                    )
            } else if (state is LyricsViewModel.State.NotFound && doc == null) {
                if (!StagePreference[StageOption.HideNotice])
                    Text(
                        stringResource(R.string.immersive_lyrics_none),
                        Modifier.align(Alignment.Center),
                        style = Immersive.Subhead,
                    )
            } else CircularProgressIndicator(Modifier.align(Alignment.Center))
            if (!floating && doc?.type != LyricsType.Static && view.activeLineDirection != null) {
                com.music.spotui.ui.components.FollowLyricsButton(
                    Modifier.align(Alignment.BottomCenter)
                ) {
                    view.scrollToActive()
                }
            }
        }
    }
    val scene: @Composable (Modifier, Boolean) -> Unit = { frame, inline ->
        SpicyCinema(
            track,
            lyricsOnLeft,
            {
                lyricsOnLeft = !lyricsOnLeft
                prefs.edit().putBoolean("cinema_lyrics_left", lyricsOnLeft).apply()
            },
            romanize,
            {
                romanize = !romanize
                prefs.edit().putBoolean("romanize", romanize).apply()
            },
            state is LyricsViewModel.State.NotFound && doc == null,
            { cinema = false },
            inline,
            frame,
            document,
            scale,
            state is LyricsViewModel.State.Loading && doc == null,
            lyricsBody,
        )
    }
    val content: @Composable (Modifier) -> Unit = { frame ->
        Column(frame) {
            val viewport: @Composable () -> Unit = {
                if (floating && document == null) lyricsBody(Modifier.weight(1f).fillMaxWidth())
                else scene(Modifier.weight(1f).fillMaxWidth(), true)
            }
            val bottom = StagePreference[StageOption.BottomControls]
            if (bottom) viewport()
            if (!floating)
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            "Spicy Lyrics",
                            style = Immersive.BodyStrong,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                        if (doc?.type == LyricsType.Static)
                            Text(
                                stringResource(R.string.spicy_static_reading),
                                style = Immersive.Caption,
                                maxLines = 1,
                            )
                    }
                    IconButton(onClick = { cinema = true }) {
                        Icon(Icons.Rounded.Theaters, stringResource(R.string.spicy_cinema))
                    }
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(
                                Icons.Rounded.MoreHoriz,
                                stringResource(R.string.content_description_context_menu),
                            )
                        }
                        CelestifyMenu(menu, { menu = false }) {
                            @Composable
                            fun action(label: String, run: () -> Unit) =
                                DropdownMenuItem(
                                    text = { Text(label) },
                                    onClick = {
                                        menu = false
                                        run()
                                    },
                                )
                            if (StagePreference[StageOption.Diagnostics])
                                action(stringResource(R.string.spicy_diagnostics)) {
                                    showDiagnostics = true
                                }
                            if (
                                StagePreference[StageOption.Popup] &&
                                    context !is FloatingLyricsActivity &&
                                    context.packageManager.hasSystemFeature(
                                        android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE
                                    )
                            ) {
                                action(stringResource(R.string.spicy_floating)) {
                                    context.startActivity(
                                        android.content
                                            .Intent(context, FloatingLyricsActivity::class.java)
                                            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                    )
                                }
                            }
                            action(stringResource(R.string.spicy_cinema)) { cinema = true }
                            action(
                                stringResource(R.string.spicy_romanize) + if (romanize) " ✓" else ""
                            ) {
                                romanize = !romanize
                                prefs.edit().putBoolean("romanize", romanize).apply()
                            }
                            if (source != null && doc === online)
                                action(stringResource(R.string.spicy_translate)) {
                                    vm.toggleTranslation(java.util.Locale.getDefault().language)
                                }
                            action(
                                stringResource(R.string.spicy_size) +
                                    " · " +
                                    (scale * 100).toInt() +
                                    "%"
                            ) {
                                scale =
                                    when {
                                        scale < 1f -> 1f
                                        scale < 1.2f -> 1.2f
                                        else -> 0.85f
                                    }
                                prefs.edit().putFloat("size", scale).apply()
                            }
                            action(stringResource(R.string.spicy_import)) {
                                persist = true
                                importTrack = track
                                picker.launch(arrayOf("*/*"))
                            }
                            action(stringResource(R.string.spicy_preview)) {
                                persist = false
                                importTrack = track
                                picker.launch(arrayOf("*/*"))
                            }
                            if (local != null)
                                action(stringResource(R.string.spicy_restore)) {
                                    scope.launch {
                                        val restored =
                                            withContext(Dispatchers.IO) {
                                                if (!SpicyImports.discardPreview(track))
                                                    SpicyImports.remove(context, track)
                                                SpicyImports.read(context, track)
                                            }
                                        revision++
                                        local = restored
                                    }
                                }
                            if (track.isNotBlank())
                                action(stringResource(R.string.lyrics_reload)) {
                                    reload++
                                    SongPlayer.currentLyricsTrack()?.let {
                                        vm.load(it, force = true)
                                    }
                                }
                        }
                    }
                }
            if (!bottom) viewport()
        }
    }
    if (cinema) scene(Modifier.fillMaxSize(), false) else content(modifier.padding(inset))
}
