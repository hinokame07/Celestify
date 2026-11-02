/*
 * Spicy Lyrics Cinema View — Spikerko and contributors, AGPL-3.0.
 * The layout, icons and skins shipped in assets/spicy-cinema/upstream are from 34ad8c6.
 * This host connects the original stage to the Android media session and native lyric renderer.
 */
package com.music.spotui.ui.immersive.lyrics

import android.graphics.Bitmap
import android.util.Base64
import android.view.WindowManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.*
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.myspoti.engine.R
import com.bumptech.glide.Glide
import com.music.spotui.data.DataSaver
import com.music.spotui.data.preferences.*
import com.music.spotui.di.SongPlayer
import com.music.spotui.ui.components.VideoSurface
import com.music.spotui.ui.immersive.player.rememberPlayerVolume
import com.music.spotui.ui.look.*
import com.music.spotui.ui.viewmodel.PlayerViewModel
import com.music.spotui.video.MusicVideoController
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.*
import org.json.JSONObject

@Composable
internal fun SpicyCinema(
    track: String,
    lyricsOnLeft: Boolean,
    onToggleSide: () -> Unit,
    romanize: Boolean,
    onRomanize: () -> Unit,
    empty: Boolean,
    onDismiss: () -> Unit,
    inline: Boolean,
    modifier: Modifier,
    document: String?,
    scale: Float,
    loading: Boolean,
    lyrics: @Composable (Modifier) -> Unit,
) {
    val content: @Composable () -> Unit = {
        val context = LocalContext.current
        val vm: PlayerViewModel = viewModel()
        val volume = rememberPlayerVolume()
        val title = vm.currentSongTitle.value
        val artist = vm.currentSongSinger.value
        val cover = vm.currentSongCoverUri.value
        val playing = vm.currentSongPlayingState.value
        val remote = SongPlayer.activeDevice.value != null
        val enabled = !inline && MusicVideoPref.on && !remote && !DataSaver.active
        val mv = MusicVideoController
        var startedHere by remember { mutableStateOf(false) }
        DisposableEffect(Unit) {
            if (!inline) mv.attachPlayerScreen()
            onDispose {
                if (startedHere) mv.setOn(false)
                if (!inline) mv.detachPlayerScreen()
            }
        }
        LaunchedEffect(track, enabled, SongPlayer.isBuffering) {
            if (enabled && !SongPlayer.isBuffering && track == SongPlayer.currentTrackId)
                mv.prepare(track, title, artist, SongPlayer.getDuration())
            if (!enabled && startedHere) {
                mv.setOn(false)
                startedHere = false
            }
        }
        val videoReady =
            enabled && (mv.state.value as? MusicVideoController.State.Ready)?.trackId == track
        val video = videoReady && mv.on.value
        val reduced = rememberReduceMotion()
        val dynamic = AtmospherePref.dynamicColors
        val motion = StagePreference[StageOption.MotionBackground] && !reduced
        val energy by app.myspoti.power.EnergySettings.state.collectAsStateWithLifecycle()
        val pref = StagePreference
        val popup = LocalFloatingLyrics.current
        val background = pref.background
        val canvasAllowed =
            !inline &&
                pref[StageOption.Canvas] &&
                background == StageBackground.Dynamic &&
                motion &&
                dynamic &&
                energy.policy.allowCanvas &&
                !DataSaver.active &&
                !(DataSaver.metered && isCanvasWifiOnly(context)) &&
                track == SongPlayer.currentTrackId
        LaunchedEffect(track, canvasAllowed, SongPlayer.isBuffering) {
            vm.loadCanvas(if (canvasAllowed) track else "", allowFetch = !SongPlayer.isBuffering)
        }
        val canvas =
            vm.canvasState.value.takeIf { canvasAllowed && it.trackId == track }?.url.orEmpty()
        var fullscreen by rememberSaveable { mutableStateOf(false) }
        var options by remember { mutableStateOf(false) }
        val dialogWindow =
            if (inline) null else (LocalView.current.parent as? DialogWindowProvider)?.window
        DisposableEffect(dialogWindow, fullscreen) {
            val bars = dialogWindow?.let { WindowCompat.getInsetsController(it, it.decorView) }
            dialogWindow?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            if (fullscreen) {
                bars?.systemBarsBehavior =
                    WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                bars?.hide(WindowInsetsCompat.Type.systemBars())
            } else bars?.show(WindowInsetsCompat.Type.systemBars())
            onDispose {
                bars?.show(WindowInsetsCompat.Type.systemBars())
                dialogWindow?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
        var bounds by remember { mutableStateOf<CinemaBounds?>(null) }
        val labels =
            mapOf(
                "like" to R.string.immersive_player_like,
                "play" to
                    if (playing) R.string.immersive_player_pause
                    else R.string.immersive_player_play,
                "previous" to R.string.immersive_player_previous,
                "next" to R.string.immersive_player_next,
                "options" to R.string.immersive_player_more,
                "side" to R.string.spicy_swap_side,
                "volume" to R.string.cinema_volume,
                "seek" to R.string.cinema_seek,
                "compact" to R.string.cinema_layout,
                "controls" to R.string.cinema_controls,
                "fullscreen" to R.string.video_fullscreen_enter,
                "romanize" to R.string.spicy_romanize,
                "shuffle" to R.string.immersive_player_shuffle_on,
                "repeat" to R.string.immersive_player_repeat_all,
                "close" to R.string.immersive_player_close,
            )
        val settings =
            JSONObject()
                .put("smoothScrolling", pref[StageOption.Smooth])
                .put("keepOverlappingLines", pref[StageOption.Overlap])
                .put("popup", popup)
                .put("seekFadeCompensation", pref[StageOption.SeekFade])
                .put("scrollLeadEnabled", pref[StageOption.Lead])
                .put("scrollLeadMs", pref.leadMs)
                .put("joinSplitWords", pref[StageOption.JoinWords])
                .put(
                    "simpleLyricsMode",
                    pref.style in listOf(StageStyle.Simple, StageStyle.Refreshed),
                )
                .put("minimalLyricsMode", pref.style == StageStyle.Minimal)
                .put("refreshedSimpleLyrics", pref.style == StageStyle.Refreshed)
                .put("backgroundLinePop", pref[StageOption.BackgroundVocals])
                .put("duets", pref[StageOption.Duets])
                .put("credits", pref[StageOption.Credits])
                .put("animationFpsCap", pref.fps)
                .put("animationFpsCapEnabled", pref[StageOption.LimitFrames])
        val model =
            JSONObject()
                .put("title", title)
                .put("hasArtwork", cover.isNotBlank())
                .put("artist", artist)
                .put("canvas", canvas)
                .put("playing", playing)
                .put("inline", inline)
                .put("popup", popup)
                .put("popupDock", pref[StageOption.PopupDock])
                .put("refinedCredits", pref[StageOption.RefinedCredits])
                .put("track", track)
                .put("loading", loading)
                .put("skeleton", pref[StageOption.Skeleton])
                .put("scale", scale)
                .put("settings", settings)
                .put("glow", AtmospherePref.lyricsGlow)
                .put("volumeSlider", pref[StageOption.Volume])
                .put("timeline", pref[StageOption.Timeline])
                .put("locked", pref[StageOption.LockedCover])
                .put("hover", pref[StageOption.Hover])
                .put("glassSlider", pref[StageOption.GlassSlider])
                .put("refined", pref[StageOption.RefinedColors])
                .put("systemFont", pref[StageOption.SystemFont])
                .put("preview", pref[StageOption.ScrubPreview])
                .put("bg", if (dynamic) background.name.lowercase() else "none")
                .put("blur", pref.blur)
                .put("lyricsLeft", lyricsOnLeft)
                .put("video", video)
                .put("romanize", romanize)
                .put("fullscreen", fullscreen)
                .put("shuffle", vm.shuffleState.value)
                .put("repeat", SongPlayer.repeatMode.value)
                .put("liked", vm.likeState.value)
                .put("empty", empty)
                .put("reduced", reduced)
                .put("motion", motion && dynamic && energy.policy.allowCanvas)
                .put("labels", JSONObject(labels.mapValues { stringResource(it.value) }))
                .toString()
        val image = stageImage(cover)
        val artistUri by
            produceState("", artist, background, dynamic) {
                value = ""
                if (background == StageBackground.Artist && dynamic)
                    value =
                        withContext(Dispatchers.IO) {
                            try {
                                com.music.spotui.di.Graph.api.lyricArtistBackdrop(
                                    artist.substringBefore(",")
                                )
                            } catch (e: CancellationException) {
                                throw e
                            } catch (_: Exception) {
                                ""
                            }
                        }
            }
        val artistImage = stageImage(artistUri)
        var fallback by remember(document) { mutableStateOf(false) }
        val life by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsState()
        val session = LocalCinemaSession.current
        BoxWithConstraints(
            modifier
                .background(Color.Black)
                .then(if (fullscreen || inline) Modifier else Modifier.systemBarsPadding())
                .displayCutoutPadding()
        ) {
            if (session.unavailable) {
                Column(Modifier.fillMaxSize()) {
                    Text(stringResource(R.string.spicy_native_recovery))
                    lyrics(Modifier.weight(1f).fillMaxWidth())
                    if (!inline)
                        TextButton(onClick = onDismiss) {
                            Text(stringResource(R.string.immersive_player_close))
                        }
                }
                return@BoxWithConstraints
            }
            val w = maxWidth
            val h = maxHeight
            fun area(r: androidx.compose.ui.geometry.Rect) =
                Modifier.absoluteOffset(x = w * r.left, y = h * r.top)
                    .size(w * r.width, h * r.height)
            val b = bounds
            if (video && b != null)
                Box(
                    area(b.media).background(Color.Black),
                    contentAlignment = androidx.compose.ui.Alignment.Center,
                ) {
                    VideoSurface()
                }
            CinemaSurface(
                model,
                image,
                artistImage,
                document.takeUnless { fallback },
                life.isAtLeast(Lifecycle.State.STARTED),
                onBounds = { bounds = it },
                progress = {
                    val p = SongPlayer.getCurrentPosition()
                    val t =
                        com.music.spotui.data.entity.LyricTiming.position(
                            p,
                            com.music.spotui.di.OutputLag.ms(),
                            AtmospherePref.lyricsOffsetMs,
                        )
                    "$p,${SongPlayer.getDuration()},${volume.read()},$t,${playing && !SongPlayer.isBuffering},${SongPlayer.speed.value}"
                },
                onAction = { name, value ->
                    when (name) {
                        "nativeFallback" -> fallback = true
                        "lyricSeek" ->
                            SongPlayer.seekTo(
                                com.music.spotui.data.entity.LyricTiming.seekPosition(
                                    value.toLong(),
                                    AtmospherePref.lyricsOffsetMs,
                                )
                            )
                        "close" -> onDismiss()
                        "side" -> onToggleSide()
                        "romanize" -> onRomanize()
                        "options" -> options = true
                        "fullscreen" -> fullscreen = !fullscreen
                        "play" -> if (playing) SongPlayer.pause() else SongPlayer.play()
                        "previous" -> SongPlayer.previous()
                        "next" -> SongPlayer.swipeNext()
                        "shuffle" -> vm.updateShuffleState(!vm.shuffleState.value)
                        "repeat" -> SongPlayer.cycleRepeat()
                        "like" -> vm.updateLikeState(!vm.likeState.value)
                        "seek" -> SongPlayer.seekTo((value * SongPlayer.getDuration()).toLong())
                        "volume" -> {
                            volume.drag(value)
                            volume.release()
                        }
                    }
                },
            )
            if (
                (document == null || fallback) &&
                    !(loading && pref[StageOption.Skeleton]) &&
                    b != null &&
                    (inline || !empty || b.lyrics.top > 0f)
            )
                lyrics(if (inline) Modifier.fillMaxSize() else area(b.lyrics))
        }
        if (options)
            AlertDialog(
                onDismissRequest = { options = false },
                title = { Text("Spicy Lyrics · Cinema") },
                text = {
                    Column {
                        if (videoReady)
                            TextButton({
                                mv.setOn(!video)
                                startedHere = !video
                                options = false
                            }) {
                                Text(
                                    stringResource(
                                        if (video) R.string.av_switch_to_audio
                                        else R.string.av_switch_to_video
                                    )
                                )
                            }
                        for (option in
                            listOf(
                                StageOption.MotionBackground,
                                StageOption.Smooth,
                                StageOption.LimitFrames,
                            )) {
                            Row(
                                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                            ) {
                                Text(stringResource(option.label), Modifier.weight(1f))
                                Switch(pref[option], { pref.set(option, it) })
                            }
                        }
                    }
                },
                confirmButton = {
                    TextButton({ options = false }) { Text(stringResource(android.R.string.ok)) }
                },
            )
    }
    if (inline) content()
    else
        Dialog(
            onDismissRequest = onDismiss,
            properties =
                DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
            content = content,
        )
}

@Composable
private fun stageImage(cover: String): String {
    val context = LocalContext.current
    val image by
        key(cover) {
            produceState("") {
                if (cover.isNotBlank())
                    value =
                        withContext(Dispatchers.IO) {
                            val loader = Glide.with(context.applicationContext)
                            val request =
                                loader
                                    .asBitmap()
                                    .load(app.myspoti.host.android.Covers.large(cover))
                                    .override(720)
                                    .disallowHardwareConfig()
                                    .submit()
                            try {
                                val bytes = ByteArrayOutputStream()
                                runInterruptible { request.get() }
                                    .compress(Bitmap.CompressFormat.JPEG, 88, bytes)
                                "data:image/jpeg;base64," +
                                    Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
                            } catch (e: CancellationException) {
                                throw e
                            } catch (_: Exception) {
                                ""
                            } finally {
                                loader.clear(request)
                            }
                        }
            }
        }
    return image
}
