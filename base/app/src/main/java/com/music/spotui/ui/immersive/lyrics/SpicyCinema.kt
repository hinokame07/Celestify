/*
 * Cinema View adapted from Spicy Lyrics' fullscreen/cinema presentation:
 * https://github.com/Spikerko/spicy-lyrics/tree/34ad8c683204c522f227060475bf4f8aae36508e
 * In particular components/Utils/Fullscreen.ts and components/Pages/PageView.ts.
 * Copyright Spikerko and contributors, AGPL-3.0. Android/Compose adaptation for Celestify,
 * 2026-11-02. Complete corresponding source and license notices ship with this project.
 */
@file:OptIn(com.bumptech.glide.integration.compose.ExperimentalGlideComposeApi::class)

package com.music.spotui.ui.immersive.lyrics

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.myspoti.engine.R
import com.bumptech.glide.integration.compose.GlideImage
import com.music.spotui.data.preferences.AtmospherePref
import com.music.spotui.data.preferences.MusicVideoPref
import com.music.spotui.di.Graph
import com.music.spotui.di.SongPlayer
import com.music.spotui.ui.components.VideoSurface
import com.music.spotui.ui.components.VideoSwitchPill
import com.music.spotui.ui.components.rememberFrameClock
import com.music.spotui.ui.immersive.Immersive
import com.music.spotui.ui.look.ThinSlider
import com.music.spotui.ui.look.rememberArtworkColors
import com.music.spotui.video.MusicVideoController

internal object SpicyCinemaPolicy {
    const val TWO_PANE_MIN_WIDTH_DP = 700f
    fun twoPane(widthDp: Float): Boolean = widthDp >= TWO_PANE_MIN_WIDTH_DP
}

@Composable
internal fun SpicyCinema(
    track: String,
    lyricsOnLeft: Boolean,
    onToggleSide: () -> Unit,
    onDismiss: () -> Unit,
    lyrics: @Composable (Modifier) -> Unit,
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val title = Graph.currentSongState.title.value
        val artist = Graph.currentSongState.singer.value
        val cover = Graph.currentSongState.coverUri.value
        val playing = Graph.currentSongState.playingState.value
        val reduced = com.music.spotui.ui.look.rememberReduceMotion()
        val palette = rememberArtworkColors(cover.takeIf { it.isNotBlank() && AtmospherePref.dynamicColors })
        val mv = MusicVideoController
        DisposableEffect(mv) {
            mv.attachPlayerScreen()
            onDispose { mv.detachPlayerScreen() }
        }
        LaunchedEffect(track, title, artist) {
            if (MusicVideoPref.on) mv.prepare(track, title, artist, SongPlayer.getDuration())
        }
        val ready = mv.state.value as? MusicVideoController.State.Ready
        val videoReady = ready?.trackId == track && SongPlayer.activeDevice.value == null &&
            !com.music.spotui.data.DataSaver.active && MusicVideoPref.on
        LaunchedEffect(videoReady) { if (videoReady) mv.warm() }
        val videoOn = videoReady && mv.on.value

        BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black)) {
            val tablet = SpicyCinemaPolicy.twoPane(maxWidth.value)
            if (!videoOn) {
                if (AtmospherePref.dynamicColors && StagePreference[StageOption.MotionBackground] && !reduced) {
                    com.music.spotui.ui.look.MeshGradientBackground(palette, trackKey = track, continuous = false)
                    Spacer(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .56f)))
                } else com.music.spotui.ui.immersive.CelestialPlayerBackground(palette)
            }

            if (tablet) {
                Row(
                    Modifier.fillMaxSize().padding(top = 82.dp, bottom = 116.dp, start = 28.dp, end = 28.dp),
                    horizontalArrangement = Arrangement.spacedBy(22.dp),
                ) {
                    if (lyricsOnLeft) {
                        CinemaLyricsPane(Modifier.weight(.57f), lyrics)
                        CinemaMediaPane(Modifier.weight(.43f), cover, videoOn)
                    } else {
                        CinemaMediaPane(Modifier.weight(.43f), cover, videoOn)
                        CinemaLyricsPane(Modifier.weight(.57f), lyrics)
                    }
                }
            } else {
                Column(Modifier.fillMaxSize().padding(top = 72.dp, bottom = 112.dp)) {
                    if (videoOn) CinemaMediaPane(Modifier.fillMaxWidth().heightIn(max = 230.dp), cover, true)
                    CinemaLyricsPane(Modifier.weight(1f).fillMaxWidth(), lyrics, compact = true)
                }
            }

            Row(
                Modifier.fillMaxWidth().systemBarsPadding().padding(horizontal = if (tablet) 28.dp else 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(title, style = Immersive.Headline.copy(color = Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(artist, style = Immersive.Caption.copy(color = Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (tablet) IconButton(onClick = onToggleSide) {
                    Icon(Icons.Rounded.SwapHoriz, stringResource(R.string.spicy_swap_side), tint = Color.White)
                }
                if (videoReady) {
                    Spacer(Modifier.width(4.dp))
                    VideoSwitchPill(videoOn)
                }
                Spacer(Modifier.width(4.dp))
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Rounded.Close, stringResource(R.string.lyrics_fullscreen_close_button_readout_value), tint = Color.White)
                }
            }

            CinemaControls(
                playing = playing,
                modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .navigationBarsPadding().padding(horizontal = if (tablet) 42.dp else 20.dp, vertical = 12.dp),
            )
        }
    }
}

@Composable
private fun CinemaLyricsPane(
    modifier: Modifier,
    lyrics: @Composable (Modifier) -> Unit,
    compact: Boolean = false,
) {
    Box(
        modifier.clip(RoundedCornerShape(if (compact) 0.dp else 28.dp))
            .background(Color.Black.copy(alpha = if (compact) .20f else .34f)),
    ) { lyrics(Modifier.fillMaxSize()) }
}

@Composable
private fun CinemaMediaPane(modifier: Modifier, cover: String, videoOn: Boolean) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Box(
            Modifier.fillMaxSize().clip(RoundedCornerShape(28.dp)).background(Color.Black.copy(alpha = .35f)),
            contentAlignment = Alignment.Center,
        ) {
            if (videoOn) {
                VideoSurface(Modifier.fillMaxWidth(), active = true)
            } else {
                GlideImage(
                    model = cover.takeIf(String::isNotBlank),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .28f)))))
            }
        }
    }
}

@Composable
private fun CinemaControls(playing: Boolean, modifier: Modifier = Modifier) {
    val duration = SongPlayer.getDuration().coerceAtLeast(1L)
    val frame = rememberFrameClock(playing, fps = 15)
    var dragged by remember { mutableStateOf<Float?>(null) }
    val progress = dragged ?: run { frame.value; (SongPlayer.getCurrentPosition().toFloat() / duration).coerceIn(0f, 1f) }
    Column(
        modifier.clip(RoundedCornerShape(28.dp)).background(Color.Black.copy(alpha = .48f)).padding(horizontal = 18.dp, vertical = 8.dp),
    ) {
        ThinSlider(
            value = progress,
            onValueChange = { dragged = it },
            onValueChangeFinished = { dragged?.let { SongPlayer.seekTo((it * duration).toLong()) }; dragged = null },
            activeColor = Color.White,
            inactiveColor = Color.White.copy(alpha = .28f),
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            IconButton({ SongPlayer.previous() }) { Icon(Icons.Rounded.SkipPrevious, stringResource(R.string.immersive_player_previous), tint = Color.White) }
            Spacer(Modifier.width(22.dp))
            Box(
                Modifier.size(58.dp).clip(RoundedCornerShape(50)).background(Color.White)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                        if (playing) SongPlayer.pause() else SongPlayer.play()
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    stringResource(if (playing) R.string.immersive_player_pause else R.string.immersive_player_play),
                    tint = Color.Black, modifier = Modifier.size(34.dp))
            }
            Spacer(Modifier.width(22.dp))
            IconButton({ SongPlayer.next() }) { Icon(Icons.Rounded.SkipNext, stringResource(R.string.immersive_player_next), tint = Color.White) }
        }
    }
}
