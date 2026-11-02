package com.music.spotui.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import com.music.spotui.ui.immersive.Immersive

@Composable
internal fun CelestifyMenu(expanded: Boolean, onDismissRequest: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismissRequest,
        shape = Immersive.Card, containerColor = Immersive.Raised,
        tonalElevation = 0.dp, shadowElevation = 10.dp,
        border = BorderStroke(0.75.dp, Immersive.GlassEdge), content = content)
}
