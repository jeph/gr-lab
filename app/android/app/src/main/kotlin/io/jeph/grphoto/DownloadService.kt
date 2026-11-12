package io.jeph.grphoto

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.IBinder
import android.os.PowerManager
import kotlin.math.roundToInt

/**
 * Keeps GR Photo running while it downloads with the app not in front, and
 * shows the download queue as a notification with its progress, a Pause or
 * Resume button and Cancel all.
 *
 * A foreground service is what keeps Android from freezing or killing the
 * process, and so from releasing its request for the camera's network. Its
 * type is `connectedDevice`, the camera being a device reached over Wi-Fi;
 * `dataSync` is limited to six hours a day. While shots are transferred it
 * holds a partial wake lock, so the transfer goes on with the screen off; a
 * paused queue holds none. No Wi-Fi lock: the only kind Android still
 * honours works while the app is in front with the screen on.
 *
 * The service does no work itself. The Dart side runs the downloads and
 * says what to show ([show], [hide]); the notification's buttons go back to
 * it through [onAction]. Everything here runs on the main thread.
 */
class DownloadService : Service() {
    data class Status(
        val paused: Boolean,
        val title: String,
        val detail: String,
        val camera: String,
        val fraction: Double,
        val toggle: String,
        val cancel: String,
        val channel: String,
    )

    companion object {
        private const val CHANNEL_ID = "downloads"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_TOGGLE = "io.jeph.grphoto.downloads.TOGGLE"
        private const val ACTION_CANCEL = "io.jeph.grphoto.downloads.CANCEL"
        private const val PROGRESS_STEPS = 1000

        // Renewed with every status, about once a second while a file
        // transfers, so it only runs out when the Dart side has stopped.
        private const val WAKE_LOCK_TIMEOUT_MS = 10 * 60 * 1000L

        /** Receives `pause`, `resume` or `cancel` when the user presses a button. */
        var onAction: ((String) -> Unit)? = null

        /** The status shown last, kept after [hide] for a service still starting. */
        private var status: Status? = null
        private var wanted = false
        private var starting = false
        private var running: DownloadService? = null

        /**
         * Shows [next], starting the service when it is not running. Throws
         * `ForegroundServiceStartNotAllowedException` (an
         * [IllegalStateException]) when Android refuses the start because
         * the app is in the background.
         */
        fun show(context: Context, next: Status) {
            status = next
            wanted = true
            val service = running
            if (service != null) {
                service.post(next)
                return
            }
            if (starting) return
            context.startForegroundService(Intent(context, DownloadService::class.java))
            starting = true
        }

        /** Removes the notification and stops the service. */
        fun hide() {
            wanted = false
            running?.stop()
        }
    }

    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private val wakeLock by lazy {
        getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "grphoto:downloads")
            .apply { setReferenceCounted(false) }
    }
    private var channelName: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        starting = false
        val shown = status
        if (shown == null) {
            // A button of a notification left from a process that has died.
            stopSelf()
            return START_NOT_STICKY
        }
        when (intent?.action) {
            ACTION_TOGGLE -> onAction?.invoke(if (shown.paused) "resume" else "pause")
            ACTION_CANCEL -> onAction?.invoke("cancel")
        }
        // Android requires this of a service started with
        // startForegroundService, even one that is to stop at once.
        startForeground(
            NOTIFICATION_ID,
            notification(shown),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        if (wanted) keepAwake(shown) else stop()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (running === this) running = null
        super.onDestroy()
    }

    private fun post(next: Status) {
        notifications.notify(NOTIFICATION_ID, notification(next))
        keepAwake(next)
    }

    private fun stop() {
        // A status that comes after this starts the service anew.
        running = null
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun keepAwake(shown: Status) {
        if (shown.paused) releaseWakeLock() else wakeLock.acquire(WAKE_LOCK_TIMEOUT_MS)
    }

    private fun releaseWakeLock() {
        if (wakeLock.isHeld) wakeLock.release()
    }

    private fun notification(shown: Status): Notification {
        if (channelName != shown.channel) {
            // Low importance: shown without sound. Creating it again renames it
            // when the app's language changed.
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, shown.channel, NotificationManager.IMPORTANCE_LOW),
            )
            channelName = shown.channel
        }
        // The launcher's own intent, so tapping brings the running app forward.
        val open = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setClass(this, MainActivity::class.java)
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle(shown.title)
            .setContentText(shown.detail)
            .setSubText(shown.camera)
            .setProgress(PROGRESS_STEPS, (shown.fraction * PROGRESS_STEPS).roundToInt(), false)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            // Without this Android holds the notification back for ten seconds.
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE))
            .addAction(button(ACTION_TOGGLE, shown.toggle))
            .addAction(button(ACTION_CANCEL, shown.cancel))
            .build()
    }

    private fun button(action: String, label: String): Notification.Action {
        val press = Intent(this, DownloadService::class.java).setAction(action)
        val icon: Icon? = null
        return Notification.Action.Builder(
            icon,
            label,
            PendingIntent.getService(this, 0, press, PendingIntent.FLAG_IMMUTABLE),
        ).build()
    }
}
