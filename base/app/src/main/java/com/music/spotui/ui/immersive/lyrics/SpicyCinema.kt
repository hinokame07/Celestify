/* Native Android host for the Spicy Lyrics Mobile renderer. See THIRD_PARTY_NOTICES.md. */
package com.music.spotui.ui.immersive.lyrics

import android.view.WindowManager
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.*
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.myspoti.engine.R
import com.bumptech.glide.integration.compose.*
import com.music.spotui.data.DataSaver
import com.music.spotui.data.preferences.*
import com.music.spotui.di.SongPlayer
import com.music.spotui.ui.components.VideoSurface
import com.music.spotui.ui.immersive.player.*
import com.music.spotui.ui.look.rememberReduceMotion
import com.music.spotui.ui.screens.CanvasVideo
import com.music.spotui.ui.viewmodel.PlayerViewModel
import com.music.spotui.video.MusicVideoController

@OptIn(ExperimentalGlideComposeApi::class)
@Composable
internal fun SpicyCinema(
    track: String,
    lyricsLeft: Boolean,
    toggleSide: () -> Unit,
    onDismiss: () -> Unit,
    romanize: Boolean,
    toggleRomanize: () -> Unit,
    lyrics: @Composable (Modifier) -> Unit,
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties =
            DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        val context = LocalContext.current
        val vm: PlayerViewModel = viewModel()
        val volume = rememberPlayerVolume()
        val title = vm.currentSongTitle.value
        val artist = vm.currentSongSinger.value
        val cover = vm.currentSongCoverUri.value
        val playing = vm.currentSongPlayingState.value
        val remote = SongPlayer.activeDevice.value != null
        val enabled = MusicVideoPref.on && !remote && !DataSaver.active
        val mv = MusicVideoController
        var startedHere by remember { mutableStateOf(false) }
        DisposableEffect(Unit) {
            mv.attachPlayerScreen()
            onDispose {
                if (startedHere) mv.setOn(false)
                mv.detachPlayerScreen()
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
        val coverOnly = pref[StageOption.CoverOnly]
        val background = pref.background
        val canvasAllowed =
            !coverOnly && !video &&
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
        val showClip = !coverOnly && video
        val movingMedia = showClip || canvas.isNotBlank()
        val surface =
            remember(track, showClip, canvas, coverOnly) {
                mutableStateOf<android.view.TextureView?>(null)
            }
        val ambient = videoLight(surface.value.takeIf { movingMedia && dynamic }, playing, reduced)
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        DisposableEffect(window) {
            val bars = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
            window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            bars?.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            bars?.hide(WindowInsetsCompat.Type.systemBars())
            onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
        }
        val state =
            ImmersivePlayerState(
                title = title,
                artist = artist,
                coverUrl = cover,
                playing = playing,
                buffering = SongPlayer.isBuffering,
                positionMs = SongPlayer::getCurrentPosition,
                trackKey = track,
                durationMs = SongPlayer.getDuration(),
            )
        var options by remember { mutableStateOf(false) }
        var controls by rememberSaveable { mutableStateOf(true) }
        val showVideo = {
            mv.setOn(!video)
            startedHere = !video
            options = false
        }
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (ambient != null) CinemaVideoBackground(ambient, !motion, playing && !state.buffering)
            else SpicyBackdrop(cover, artist, playing, coverSource = true)
            NativeCinemaLayout(
                state,
                lyricsLeft,
                controls,
                toggleSide,
                { controls = !controls },
                onDismiss,
                { options = true },
                artwork = { mod ->
                    Box(mod.clip(RoundedCornerShape(12.dp))) {
                        GlideImage(
                            model = app.myspoti.host.android.Covers.large(cover),
                            contentDescription = null,
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop,
                        )
                    }
                },
                videoLayer =
                    if (!movingMedia) null
                    else
                        { mod ->
                            key(track, showClip, canvas) {
                                if (showClip)
                                    BoxWithConstraints(
                                        mod.clipToBounds(),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        val ratio = mv.aspect.floatValue.coerceIn(.4f, 3f)
                                        val width = maxOf(maxWidth, maxHeight * ratio)
                                        VideoSurface(
                                            Modifier.requiredSize(width, width / ratio),
                                            onTexture = { surface.value = it },
                                        )
                                    }
                                else
                                    CanvasVideo(
                                        canvas,
                                        playing,
                                        onFirstFrame = {},
                                        modifier = mod,
                                        onTexture = { surface.value = it },
                                    )
                            }
                        },
                lockedCover = pref[StageOption.LockedCover],
                lyrics = lyrics,
                transport = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        if (pref[StageOption.Timeline])
                            PlayerScrubber(
                                state,
                                SongPlayer::seekTo,
                                pref[StageOption.GlassSlider],
                                pref[StageOption.ScrubPreview],
                            )
                        TransportRow(
                            playing,
                            SongPlayer.isBuffering,
                            true,
                            { SongPlayer.previous() },
                            { if (playing) SongPlayer.pause() else SongPlayer.play() },
                            { SongPlayer.swipeNext() },
                        )
                        if (!pref[StageOption.Timeline])
                            PlayerScrubber(
                                state,
                                SongPlayer::seekTo,
                                pref[StageOption.GlassSlider],
                                pref[StageOption.ScrubPreview],
                            )
                    }
                },
            )
        }
        if (options)
            AlertDialog(
                onDismissRequest = { options = false },
                title = { Text(stringResource(R.string.native_cinema_title)) },
                text = {
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        Row(
                            Modifier.fillMaxWidth()
                                .toggleable(
                                    value = coverOnly,
                                    role = androidx.compose.ui.semantics.Role.Switch,
                                    onValueChange = { pref.set(StageOption.CoverOnly, it) },
                                )
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(stringResource(R.string.cinema_cover_only), Modifier.weight(1f))
                            Switch(coverOnly, null)
                        }
                        TextButton({ vm.updateLikeState(!vm.likeState.value) }) {
                            Text(
                                stringResource(
                                    if (vm.likeState.value) R.string.immersive_player_unlike
                                    else R.string.immersive_player_like
                                )
                            )
                        }
                        TextButton({ vm.updateShuffleState(!vm.shuffleState.value) }) {
                            Text(
                                stringResource(
                                    if (vm.shuffleState.value) R.string.immersive_player_shuffle_on
                                    else R.string.immersive_player_shuffle_off
                                )
                            )
                        }
                        TextButton({ SongPlayer.cycleRepeat() }) {
                            Text(
                                stringResource(
                                    when (SongPlayer.repeatMode.value) {
                                        2 -> R.string.immersive_player_repeat_one
                                        1 -> R.string.immersive_player_repeat_all
                                        else -> R.string.immersive_player_repeat_off
                                    }
                                )
                            )
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.spicy_romanize), Modifier.weight(1f))
                            Switch(romanize, { toggleRomanize() })
                        }
                        if (pref[StageOption.Volume]) VolumeRow(volume)
                        if (videoReady && !coverOnly)
                            TextButton(showVideo) {
                                Text(
                                    stringResource(
                                        if (video) R.string.av_switch_to_audio
                                        else R.string.av_switch_to_video
                                    )
                                )
                            }
                    }
                },
                confirmButton = {
                    TextButton({ options = false }) { Text(stringResource(android.R.string.ok)) }
                },
            )
    }
}

/** Controls and lyrics occupy disjoint hit regions. No screen-sized tap or drag recognizer. */
@Composable
internal fun NativeCinemaLayout(
    state: ImmersivePlayerState,
    lyricsLeft: Boolean,
    controls: Boolean,
    swap: () -> Unit,
    toggleControls: () -> Unit,
    close: () -> Unit,
    more: () -> Unit,
    artwork: @Composable (Modifier) -> Unit,
    videoLayer: (@Composable (Modifier) -> Unit)? = null,
    lockedCover: Boolean = false,
    lyrics: @Composable (Modifier) -> Unit,
    transport: @Composable () -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize().testTag("cinema")) {
        val split = maxWidth >= 600.dp && maxWidth > maxHeight
        val gutter = if (split) 24.dp else 16.dp
        val videoHeight = (maxHeight * .36f).coerceAtMost(320.dp)
        if (videoLayer != null) {
            val area =
                if (split)
                    Modifier.align(
                            if (lyricsLeft) AbsoluteAlignment.CenterRight
                            else AbsoluteAlignment.CenterLeft
                        )
                        .fillMaxHeight()
                        .fillMaxWidth(.60f)
                else Modifier.align(Alignment.TopCenter).fillMaxWidth().height(videoHeight)
            videoLayer(
                area
                    .testTag("cinema-film")
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithCache {
                        // A smoothstep falloff has zero slope where the video meets the ambient light.
                        val stops=Array(13){ i ->
                            val at=i/12f
                            val distance=if(split && lyricsLeft) 1f-at else at
                            val begin=if(split) .39f else .42f
                            val u=((distance-begin)/(1f-begin)).coerceIn(0f,1f)
                            at to Color.Black.copy(alpha=1f-u*u*(3f-2f*u))
                        }
                        val mask=if(split) Brush.horizontalGradient(*stops) else Brush.verticalGradient(*stops)
                        val shade =
                            Brush.verticalGradient(
                                listOf(
                                    Color.Black.copy(alpha = .25f),
                                    Color.Transparent,
                                    Color.Black.copy(alpha = .58f),
                                )
                            )
                        onDrawWithContent {
                            drawContent()
                            drawRect(shade)
                            drawRect(mask, blendMode = BlendMode.DstIn)
                        }
                    }
            )
        }
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = gutter)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(close, Modifier.testTag("cinema-close")) {
                    Icon(
                        Icons.Rounded.KeyboardArrowDown,
                        stringResource(R.string.immersive_player_close),
                        tint = Color.White,
                    )
                }
                Text(
                    stringResource(R.string.native_cinema_title),
                    Modifier.weight(1f),
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                    maxLines = 1,
                )
                if (split)
                    IconButton(swap, Modifier.testTag("cinema-swap")) {
                        Icon(
                            Icons.Rounded.SwapHoriz,
                            stringResource(R.string.spicy_swap_side),
                            tint = Color.White,
                        )
                    }
                IconButton(toggleControls, Modifier.testTag("cinema-controls")) {
                    Icon(
                        if (controls) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                        stringResource(
                            if (controls) R.string.native_hide_controls
                            else R.string.cinema_controls
                        ),
                        tint = Color.White,
                    )
                }
                IconButton(more, Modifier.testTag("cinema-more")) {
                    Icon(
                        Icons.Rounded.MoreHoriz,
                        stringResource(R.string.immersive_player_more),
                        tint = Color.White,
                    )
                }
            }
            val metadata: @Composable () -> Unit = {
                Text(
                    state.title,
                    color = Color.White,
                    fontSize = if (split) 23.sp else 19.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    state.artist,
                    color = Color.White.copy(alpha = .76f),
                    fontSize = 16.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (split)
                CinemaSplit(
                    lyricsLeft,
                    gutter,
                    lyrics = lyrics,
                    media = {
                        if (videoLayer != null)
                            Column(Modifier.fillMaxSize().padding(bottom = 8.dp)) {
                                Spacer(
                                    Modifier.fillMaxWidth()
                                        .weight(1f)
                                        .clickable(
                                            onClickLabel = stringResource(R.string.cinema_controls),
                                            onClick = toggleControls,
                                        )
                                )
                                metadata()
                                if (controls) transport()
                            }
                        else
                            BoxWithConstraints(Modifier.fillMaxSize()) {
                                val artSize =
                                    minOf(
                                        maxWidth,
                                        (maxHeight - (if (controls) 184.dp else 72.dp))
                                            .coerceAtLeast(48.dp),
                                    )
                                Column(
                                    Modifier.fillMaxSize(),
                                    verticalArrangement = Arrangement.Center,
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                ) {
                                    artwork(
                                        Modifier.size(artSize)
                                            .clickable(
                                                onClickLabel =
                                                    stringResource(R.string.cinema_controls),
                                                onClick = toggleControls,
                                            )
                                    )
                                    Spacer(Modifier.height(8.dp))
                                    metadata()
                                    if (controls) transport()
                                }
                            }
                    },
                )
            else {
                if (videoLayer != null)
                    Column(
                        Modifier.fillMaxWidth()
                            .height((videoHeight - 64.dp).coerceAtLeast(64.dp))
                            .clickable(
                                onClickLabel = stringResource(R.string.cinema_controls),
                                onClick = toggleControls,
                            ),
                        verticalArrangement = Arrangement.Bottom,
                    ) {
                        metadata()
                    }
                else
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        artwork(
                            Modifier.size(if (controls && !lockedCover) 80.dp else 60.dp)
                                .clickable(
                                    onClickLabel = stringResource(R.string.cinema_controls),
                                    onClick = toggleControls,
                                )
                        )
                        Column(Modifier.weight(1f)) { metadata() }
                    }
                lyrics(Modifier.weight(1f).fillMaxWidth().testTag("cinema-lyrics"))
                if (controls) transport()
            }
        }
    }
}

/** Keep both children mounted while swapping their physical positions, including in RTL locales. */
@Composable
private fun CinemaSplit(
    left: Boolean,
    gap: androidx.compose.ui.unit.Dp,
    media: @Composable () -> Unit,
    lyrics: @Composable (Modifier) -> Unit,
) {
    androidx.compose.ui.layout.Layout(
        modifier = Modifier.fillMaxSize(),
        content = {
            Box(Modifier.fillMaxSize()) { media() }
            Box(Modifier.fillMaxSize().testTag("cinema-lyrics")) { lyrics(Modifier.fillMaxSize()) }
        },
    ) { children, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val space = gap.roundToPx()
        val artworkWidth = ((width - space) / 2.4f).toInt().coerceAtLeast(0)
        val lyricWidth = (width - space - artworkWidth).coerceAtLeast(0)
        val cover =
            children[0].measure(androidx.compose.ui.unit.Constraints.fixed(artworkWidth, height))
        val words =
            children[1].measure(androidx.compose.ui.unit.Constraints.fixed(lyricWidth, height))
        layout(width, height) {
            cover.place(if (left) lyricWidth + space else 0, 0)
            words.place(if (left) 0 else artworkWidth + space, 0)
        }
    }
}
