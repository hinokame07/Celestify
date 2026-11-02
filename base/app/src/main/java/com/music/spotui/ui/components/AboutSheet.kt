package com.music.spotui.ui.components

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.myspoti.engine.BuildConfig
import app.myspoti.engine.R
import com.music.spotui.ui.immersive.Immersive

private const val ORIGIN_URL = "https://github.com/kota-zo/myspoti"

/** Celestify identity and the mandatory origin and GPL attribution. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun AboutSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    com.music.spotui.extensions.ProtectedSurfaceEffect(app.myspoti.extensions.ProtectedSurface.ABOUT)
    LookSheet(
        onDismissRequest = onDismiss,
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Immersive.Raised,
    ) {
        Column(Modifier.navigationBarsPadding().verticalScroll(rememberScrollState()).padding(bottom = 28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 20.dp)) {
                Image(
                    painterResource(R.drawable.ic_launcher_foreground), contentDescription = null,
                    modifier = Modifier.size(56.dp).clip(RoundedCornerShape(14.dp)).background(Immersive.Secondary),
                )
                Column(Modifier.padding(start = 14.dp)) {
                    Text("Celestify", color = Immersive.Text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    Text("${stringResource(R.string.settings_item_version_title)} ${BuildConfig.VERSION_NAME}",
                        color = Immersive.TextSecondary, fontSize = 13.sp)
                }
            }
            Text(stringResource(R.string.celestify_origin), color = Immersive.TextSecondary,
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 8.dp))
            Text(stringResource(R.string.celestify_credits_title), color = Immersive.Text, fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            Text(stringResource(R.string.celestify_credits_projects), color = Immersive.TextSecondary,
                fontSize = 13.sp, modifier = Modifier.padding(horizontal = 20.dp))
            AboutRow("Spicy Lyrics", "Spikerko · AGPL-3.0") { openUrl(context, "https://github.com/Spikerko/spicy-lyrics") }
            AboutRow("Celestify", stringResource(R.string.celestify_github_versions)) {
                openUrl(context, "https://github.com/hinokame07/Celestify/releases")
            }
            AboutRow(stringResource(R.string.about_github), ORIGIN_URL) { openUrl(context, ORIGIN_URL) }
        }
    }
}

private fun openUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

@Composable
private fun AboutRow(title: String, detail: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 10.dp)) {
        Text(title, color = Immersive.Text, fontSize = 16.sp)
        Text(detail, color = Immersive.TextSecondary, fontSize = 12.sp)
    }
}
