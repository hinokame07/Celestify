package com.music.spotui.data.api

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import app.myspoti.engine.BuildConfig
import app.myspoti.engine.R
import com.music.spotui.data.preferences.AutoUpdateCheckPref
import kotlinx.coroutines.*

internal object ReleaseNotifications {
    private const val ID = 0x43454c
    private const val CHANNEL = "celestify_releases"
    private const val SEEN = "last_announced"

    private fun prefs(context: Context) =
        context.getSharedPreferences("celestify_updates", Context.MODE_PRIVATE)

    fun schedule(context: Context, enabled: Boolean) {
        val jobs = context.getSystemService(JobScheduler::class.java)
        if (!enabled || BuildConfig.UPDATE_REPO.isBlank()) {
            jobs.cancel(ID)
            context.getSystemService(NotificationManager::class.java).cancel(ID)
            return
        }
        if (jobs.getPendingJob(ID)?.intervalMillis == UpdateChecker.PERIODIC_MS) return
        jobs.schedule(
            JobInfo.Builder(ID, ComponentName(context, ReleaseCheckJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(UpdateChecker.PERIODIC_MS)
                .setPersisted(true)
                .build()
        )
    }

    internal fun alreadySeen(version: String, seen: String?) =
        seen != null && !UpdateChecker.isNewer(version, seen)

    fun shownInApp(context: Context, version: String) {
        val p = prefs(context)
        val seen = p.getString(SEEN, null)
        if (seen != version && alreadySeen(version, seen)) return
        p.edit().putString(SEEN, version).apply()
        context.getSystemService(NotificationManager::class.java).cancel(ID)
    }

    fun post(context: Context, release: UpdateChecker.Release) {
        if (
            !AutoUpdateCheckPref.on ||
                alreadySeen(release.version, prefs(context).getString(SEEN, null))
        )
            return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (
            !nm.areNotificationsEnabled() ||
                (Build.VERSION.SDK_INT >= 33 &&
                    context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED)
        )
            return
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                context.getString(R.string.release_channel),
                NotificationManager.IMPORTANCE_DEFAULT,
            )
        )
        if (nm.getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE)
            return
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        val tap =
            PendingIntent.getActivity(
                context,
                ID,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        nm.notify(
            ID,
            Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.msp_ic_notification)
                .setContentTitle(context.getString(R.string.release_notice_title, release.version))
                .setContentText(context.getString(R.string.release_notice_detail))
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .build(),
        )
        prefs(context).edit().putString(SEEN, release.version).apply()
    }
}

/** Android owns the schedule and only starts a check when a network is available. */
class ReleaseCheckJob : JobService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var check: Job? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (!AutoUpdateCheckPref.on) return false
        check =
            scope.launch {
                try {
                    UpdateChecker.check(this@ReleaseCheckJob)?.let {
                        ReleaseNotifications.post(this@ReleaseCheckJob, it)
                    }
                } finally {
                    if (isActive) jobFinished(params, false)
                }
            }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        check?.cancel()
        return AutoUpdateCheckPref.on
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
