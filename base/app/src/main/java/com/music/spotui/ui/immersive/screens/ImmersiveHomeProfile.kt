/*
 * Adapted from BitChord (https://github.com/kushagrasinghx/BitChord), GPL-3.0-or-later,
 * sharedUi/src/jvmSharedMain/kotlin/com/music/bitchord/ui/screens/HomeScreen.kt at edc1e6f.
 * The sheet's rows are those of Myspoti's Classic Home profile sheet. Modified for Myspoti, 2026-10.
 */
package com.music.spotui.ui.immersive.screens

import com.music.spotui.ui.components.ProfilePhotoActions
import com.music.spotui.ui.components.localProfilePhoto
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.Brush
import com.music.spotui.ui.immersive.pages.ImmersiveGroupRow
import com.music.spotui.ui.immersive.sheets.ImmersiveSheet
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.myspoti.engine.R
import com.music.spotui.data.api.ProfileCache
import com.music.spotui.di.Graph
import com.music.spotui.di.SessionActions
import com.music.spotui.ui.components.AboutSheet
import com.music.spotui.ui.immersive.Immersive
import com.music.spotui.ui.immersive.components.ImmersiveCover
import com.music.spotui.ui.immersive.components.immersiveClickable
import com.music.spotui.ui.navigation.Routes
import com.music.spotui.ui.navigation.profileRoute
import com.music.spotui.ui.screens.AccountBrowser

/**
 * The profile picture as a disc (the first letter of the name until it loads), opening [onClick];
 * null when the caller takes the tap on a wider area around it.
 */
@Composable
internal fun ProfileDisc(onClick: (() -> Unit)?, modifier: Modifier = Modifier) {
    val avatar = localProfilePhoto() ?: ProfileCache.imageUrl
    val initial = ProfileCache.name?.trim()?.firstOrNull()?.uppercase() ?: "•"
    AvatarDisc(
        url = avatar,
        initial = initial,
        contentDescription = stringResource(R.string.recently_played_user_profile),
        onClick = onClick,
        modifier = modifier,
    )
}

/** A round avatar: the picture at [url], or [initial] on the accent while there is none. */
@Composable
internal fun AvatarDisc(
    url: String?,
    initial: String,
    contentDescription: String?,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    size: Dp = 36.dp,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(size)
            .let { if (onClick != null) it.immersiveClickable(onClick = onClick) else it }
            .clip(CircleShape)
            .background(Immersive.Accent),
    ) {
        if (!url.isNullOrBlank()) {
            ImmersiveCover(
                url = url,
                modifier = Modifier.size(size),
                shape = CircleShape,
                contentDescription = contentDescription,
                border = false,
            )
        } else {
            Text(text = initial, style = Immersive.BodyStrong.copy(color = Immersive.Page, fontWeight = FontWeight.Bold))
        }
    }
}

/**
 * The profile sheet behind the avatar: account name and picture (open the public profile),
 * settings, recap, history, the account page, support, about and sign-out. The same rows and
 * actions as the Classic Home screen's sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ImmersiveProfileSheet(onOpen: (route: String) -> Unit, onDismiss: () -> Unit) {
    val name = ProfileCache.name.orEmpty()
    val avatar = localProfilePhoto() ?: ProfileCache.imageUrl
    val myId = ProfileCache.id
    val registry by com.music.spotui.extensions.Extensions.registry.collectAsState()
    val installed = registry.extensions
    var about by remember { mutableStateOf(false) }
    if (about) AboutSheet { about = false }

    ImmersiveSheet(onDismiss = onDismiss, imageUrl = avatar, maxHeightFraction = 0.94f) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            ProfileGroup {
                Row(verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                        .clickable(enabled = myId != null, role = Role.Button) { myId?.let { onOpen(profileRoute(it, name)) } }
                        .padding(16.dp)) {
                    AvatarDisc(avatar, name.trim().firstOrNull()?.uppercase() ?: "•", null, null, size = 62.dp)
                    Column(Modifier.weight(1f).padding(start = 14.dp)) {
                        Text(name.ifBlank { stringResource(R.string.immersive_screens_account) },
                            style = Immersive.Title, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        if (myId != null) Text(stringResource(R.string.view_profile), style = Immersive.Subhead)
                    }
                }
                ProfilePhotoActions()
            }
            ProfileGroup {
                ImmersiveGroupRow(stringResource(R.string.settings_title), detail = stringResource(R.string.settings_detail),
                    icon = Icons.Rounded.Settings, chevron = true, onClick = { onOpen(Routes.Settings.route) })
                ImmersiveGroupRow(stringResource(R.string.extensions_title), icon = Icons.Rounded.Extension, chevron = true,
                    detail = if (installed.isEmpty()) stringResource(R.string.extensions_row_detail)
                    else stringResource(R.string.extensions_row_count, installed.size, installed.count { it.enabled }),
                    onClick = { onOpen(Routes.Extensions.route) })
            }
            Text(stringResource(R.string.celestify_listening), style = Immersive.Headline, modifier = Modifier.padding(start = 6.dp))
            ProfileGroup {
                ImmersiveGroupRow(stringResource(R.string.recap_title), icon = Icons.Rounded.BarChart,
                    chevron = true, onClick = { onOpen(Routes.Recap.route) })
                ImmersiveGroupRow(stringResource(R.string.recents_title), icon = Icons.Rounded.History,
                    chevron = true, onClick = { onOpen(Routes.Recent.route) })
                ImmersiveGroupRow(stringResource(R.string.friends_title), icon = Icons.Rounded.People,
                    chevron = true, onClick = { onOpen(Routes.Friends.route) })
            }
            ProfileGroup {
                ImmersiveGroupRow(stringResource(R.string.immersive_screens_account_page), icon = Icons.Rounded.ManageAccounts,
                    chevron = true, onClick = { onDismiss(); AccountBrowser.open(Graph.app, AccountBrowser.ACCOUNT_URL) })
                ImmersiveGroupRow(stringResource(R.string.creator_biography_section_title), icon = Icons.Rounded.Info,
                    detail = stringResource(R.string.celestify_credits_title), chevron = true, onClick = { about = true })
            }
            ImmersiveGroupRow(stringResource(R.string.connect_device_menu_logout), destructive = true,
                onClick = { onDismiss(); SessionActions.logout(Graph.app) })
        }
    }
}

@Composable
private fun ProfileGroup(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(Immersive.Card)
        .background(Brush.verticalGradient(listOf(Immersive.Raised, Immersive.Secondary)))
        .border(0.75.dp, Immersive.Separator, Immersive.Card), content = content)
}
