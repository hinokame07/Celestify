package com.music.spotui.ui.components

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.myspoti.engine.R
import com.bumptech.glide.Glide
import com.music.spotui.data.api.ProfileCache
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

private fun Context.photoPrefs() = getSharedPreferences("celestify_profile_photos", Context.MODE_PRIVATE)
private fun Context.photoDirectory() = File(filesDir, "profile_photos")

@Composable
internal fun localProfilePhoto(): String? {
    val account = ProfileCache.id ?: return null
    val context = LocalContext.current
    val prefs = context.photoPrefs()
    var filename by remember(prefs, account) { mutableStateOf(prefs.getString(account, null)) }
    DisposableEffect(prefs, account) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { source, key ->
            if (key == account) filename = source.getString(key, null)
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        filename = prefs.getString(account, null)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return filename?.let { File(context.photoDirectory(), it).absolutePath }
}

private fun replacePhoto(context: Context, account: String, uri: Uri?) {
    val prefs = context.photoPrefs()
    val dir = context.photoDirectory()
    val photo = uri?.let {
        val glide = Glide.with(context)
        val request = glide.asBitmap().load(uri).diskCacheStrategy(com.bumptech.glide.load.engine.DiskCacheStrategy.NONE)
            .skipMemoryCache(true).centerCrop().submit(512, 512)
        try {
            val bitmap = request.get()
            dir.mkdirs()
            val file = File.createTempFile("avatar-", ".jpg", dir)
            try {
                file.outputStream().use { if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) throw IOException() }
            } catch (e: Exception) {
                file.delete()
                throw e
            }
            file
        } finally {
            glide.clear(request)
        }
    }
    synchronized(prefs) {
        val old = prefs.getString(account, null)
        if (!prefs.edit().putString(account, photo?.name).commit()) {
            throw IOException("Could not save profile photo preference")
        }
        old?.let { File(dir, it).delete() }
    }
}

@Composable
internal fun ProfilePhotoActions() {
    val account = ProfileCache.id ?: return
    val context = LocalContext.current.applicationContext
    val custom = localProfilePhoto()
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var pickerAccount by rememberSaveable { mutableStateOf<String?>(null) }
    fun update(uri: Uri?) {
        busy = true
        scope.launch {
            try {
                withContext(Dispatchers.IO) { replacePhoto(context, account, uri) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                Toast.makeText(context, R.string.profile_photo_failed, Toast.LENGTH_LONG).show()
            } finally {
                busy = false
            }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null && pickerAccount == account) update(uri)
        pickerAccount = null
    }
    androidx.compose.foundation.layout.Column(Modifier.padding(horizontal = 16.dp)) {
        TextButton(enabled = !busy, onClick = {
            pickerAccount = account
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }) { Text(stringResource(R.string.profile_photo_change)) }
        if (custom != null) TextButton(enabled = !busy, onClick = { update(null) }) {
            Text(stringResource(R.string.profile_photo_restore))
        }
    }
}
