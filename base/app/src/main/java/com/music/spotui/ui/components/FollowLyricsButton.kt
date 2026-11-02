package com.music.spotui.ui.components

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.myspoti.engine.R
import com.music.spotui.ui.immersive.Immersive

@Composable
internal fun FollowLyricsButton(modifier: Modifier, onClick: () -> Unit) {
    Button(onClick, modifier.padding(8.dp), shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = Immersive.Accent, contentColor = Immersive.OnAccent)) {
        Text(stringResource(R.string.celestify_follow_playback))
    }
}
