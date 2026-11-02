package com.music.spotui.data.api

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.Context
import com.music.spotui.data.preferences.AutoUpdateCheckPref
import com.music.spotui.di.Graph
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.*
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
class ReleaseNotificationTest {
    @Test
    fun schedulesOneNetworkJobAndAnnouncesEachReleaseOnce() {
        val app = RuntimeEnvironment.getApplication()
        Graph::class.java.getDeclaredField("app").apply {
            isAccessible = true
            set(null, app)
        }
        Shadows.shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertTrue(AutoUpdateCheckPref.on)
        repeat(2) { ReleaseNotifications.schedule(app, true) }
        val jobs = app.getSystemService(JobScheduler::class.java)
        val job =
            jobs.allPendingJobs.single { it.service.className == ReleaseCheckJob::class.java.name }
        assertTrue(job.isPersisted)
        assertEquals(JobInfo.NETWORK_TYPE_ANY, job.networkType)
        val prefs = app.getSharedPreferences("celestify_updates", Context.MODE_PRIVATE)
        prefs
            .edit()
            .putString("version", "99.1.0")
            .putString("url", "https://github.com/hinokame07/Celestify/releases/tag/v99.1.0")
            .putLong("checked_at", System.currentTimeMillis())
            .commit()
        val release = runBlocking { UpdateChecker.check(app) }!!
        val manager = app.getSystemService(NotificationManager::class.java)
        ReleaseNotifications.post(app, release)
        val notification = manager.activeNotifications.single()
        assertNotNull(notification.notification.contentIntent)
        manager.cancel(notification.id)
        ReleaseNotifications.post(app, release)
        assertEquals(0, manager.activeNotifications.size)
        ReleaseNotifications.post(app, release.copy(version = "99.2.0"))
        assertEquals(1, manager.activeNotifications.size)
        AutoUpdateCheckPref.set(app, false)
        assertNull(jobs.getPendingJob(job.id))
        assertEquals(0, manager.activeNotifications.size)
    }
}
