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
import android.os.SystemClock
import kotlin.math.roundToInt

/**
 * Keeps GR Photo running while the phone is on a camera's Wi-Fi, so that
 * its auto-disconnect and its downloads go on with the app not in front,
 * and shows that as a notification: the download queue, with its progress,
 * a Pause or Resume button and Cancel all, while there is one ([downloads]),
 * and otherwise the camera's Wi-Fi with a Disconnect button ([wifi]).
 *
 * A foreground service is what keeps Android from freezing or killing the
 * process, and so from releasing its request for the camera's network or
 * stopping the Dart timer that leaves it. Its type is `connectedDevice`,
 * the camera being a device reached over Wi-Fi; `dataSync` is limited to
 * six hours a day. Android only starts it for an app in front, so the
 * Dart side holds it from the moment it joins the camera's Wi-Fi, which
 * only happens in front, until it leaves it.
 *
 * A partial wake lock lets the Dart timers run with the screen off: while
 * shots are transferred, renewed with every status, and for the time
 * [keepAwakeFor] gives (the time left until auto-disconnect leaves the
 * Wi-Fi). A paused queue, and the Wi-Fi with the app in front or kept
 * forever, hold none. No Wi-Fi lock: the only kind Android still honours
 * works while the app is in front with the screen on.
 *
 * The service does no work itself. The Dart side runs the downloads and
 * the auto-disconnect and says what to show; the notification's buttons go
 * back to it through [onDownloadAction] and [onDisconnect]. Everything here
 * runs on the main thread.
 */
class CameraWifiService : Service() {
    data class Downloads(
        val paused: Boolean,
        val title: String,
        val detail: String,
        val camera: String,
        val fraction: Double,
        val toggle: String,
        val cancel: String,
        val channel: String,
    )

    /** The camera's Wi-Fi while there are no downloads; [text] may be empty. */
    data class Wifi(
        val title: String,
        val text: String,
        val camera: String,
        val disconnect: String,
        val channel: String,
    )

    companion object {
        private const val DOWNLOADS_CHANNEL_ID = "downloads"
        private const val WIFI_CHANNEL_ID = "camera-wifi"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_TOGGLE = "io.jeph.grphoto.downloads.TOGGLE"
        private const val ACTION_CANCEL = "io.jeph.grphoto.downloads.CANCEL"
        private const val ACTION_DISCONNECT = "io.jeph.grphoto.wifi.DISCONNECT"
        private const val PROGRESS_STEPS = 1000

        // Renewed with every status, about once a second while a file
        // transfers, so it only runs out when the Dart side has stopped.
        private const val DOWNLOAD_WAKE_LOCK_MS = 10 * 60 * 1000L

        /** Receives `pause`, `resume` or `cancel` when the user presses a button. */
        var onDownloadAction: ((String) -> Unit)? = null

        /** Called when the user pressed Disconnect. */
        var onDisconnect: (() -> Unit)? = null

        // What was shown last of each, kept when taken down for a service
        // still starting: it owes Android a notification all the same.
        private var downloads: Downloads? = null
        private var wifi: Wifi? = null
        private var downloadsWanted = false
        private var wifiWanted = false

        /** Until when the Wi-Fi keeps the phone awake, on [SystemClock.elapsedRealtime]. */
        private var wifiAwakeUntil = 0L
        private var starting = false
        private var running: CameraWifiService? = null

        /**
         * Shows the download queue, starting the service when it is not
         * running. Throws `ForegroundServiceStartNotAllowedException` (an
         * [IllegalStateException]) when Android refuses the start because
         * the app is in the background.
         */
        fun showDownloads(context: Context, next: Downloads) {
            downloads = next
            downloadsWanted = true
            update(context)
        }

        /** Takes the download queue down; the service stays for the Wi-Fi. */
        fun hideDownloads() {
            downloadsWanted = false
            update(null)
        }

        /** Like [showDownloads], for the camera's Wi-Fi. */
        fun holdWifi(context: Context, next: Wifi) {
            wifi = next
            wifiWanted = true
            update(context)
        }

        /** The phone left the camera's Wi-Fi. */
        fun releaseWifi() {
            wifiWanted = false
            wifiAwakeUntil = 0L
            update(null)
        }

        /** Keeps the phone awake for [ms] for the Wi-Fi; 0 for not at all. */
        fun keepAwakeFor(ms: Long) {
            wifiAwakeUntil = if (ms > 0) SystemClock.elapsedRealtime() + ms else 0L
            running?.keepAwake()
        }

        private fun update(context: Context?) {
            val service = running
            if (!downloadsWanted && !wifiWanted) {
                service?.stop()
                return
            }
            if (service != null) {
                service.post()
                return
            }
            if (starting || context == null) return
            context.startForegroundService(Intent(context, CameraWifiService::class.java))
            starting = true
        }
    }

    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private val wakeLock by lazy {
        getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "grphoto:camera-wifi")
            .apply { setReferenceCounted(false) }
    }
    private val channelNames = mutableMapOf<String, String>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        starting = false
        val shown = notification() ?: downloads?.let(::downloadsNotification) ?: wifi?.let(::wifiNotification)
        if (shown == null) {
            // A button of a notification left from a process that has died.
            stopSelf()
            return START_NOT_STICKY
        }
        val paused = downloads?.takeIf { downloadsWanted }?.paused
        when (intent?.action) {
            ACTION_TOGGLE -> if (paused != null) onDownloadAction?.invoke(if (paused) "resume" else "pause")
            ACTION_CANCEL -> onDownloadAction?.invoke("cancel")
            ACTION_DISCONNECT -> onDisconnect?.invoke()
        }
        // Android requires this of a service started with
        // startForegroundService, even one that is to stop at once.
        startForeground(NOTIFICATION_ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        if (downloadsWanted || wifiWanted) keepAwake() else stop()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (running === this) running = null
        super.onDestroy()
    }

    private fun post() {
        val shown = notification() ?: return
        notifications.notify(NOTIFICATION_ID, shown)
        keepAwake()
    }

    private fun stop() {
        // Something shown after this starts the service anew.
        running = null
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun keepAwake() {
        val forDownloads = if (downloadsWanted && downloads?.paused == false) DOWNLOAD_WAKE_LOCK_MS else 0L
        val forWifi = (wifiAwakeUntil - SystemClock.elapsedRealtime()).coerceAtLeast(0L)
        val ms = maxOf(forDownloads, forWifi)
        if (ms > 0) wakeLock.acquire(ms) else releaseWakeLock()
    }

    private fun releaseWakeLock() {
        if (wakeLock.isHeld) wakeLock.release()
    }

    /** What is wanted, downloads first; null when nothing is. */
    private fun notification(): Notification? {
        if (downloadsWanted) downloads?.let { return downloadsNotification(it) }
        if (wifiWanted) wifi?.let { return wifiNotification(it) }
        return null
    }

    private fun downloadsNotification(shown: Downloads): Notification =
        builder(DOWNLOADS_CHANNEL_ID, shown.channel)
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle(shown.title)
            .setContentText(shown.detail)
            .setSubText(shown.camera)
            .setProgress(PROGRESS_STEPS, (shown.fraction * PROGRESS_STEPS).roundToInt(), false)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .addAction(button(ACTION_TOGGLE, shown.toggle))
            .addAction(button(ACTION_CANCEL, shown.cancel))
            .build()

    private fun wifiNotification(shown: Wifi): Notification {
        val built = builder(WIFI_CHANNEL_ID, shown.channel)
            .setSmallIcon(R.drawable.ic_stat_wifi)
            .setContentTitle(shown.title)
            .setSubText(shown.camera)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(button(ACTION_DISCONNECT, shown.disconnect))
        if (shown.text.isNotEmpty()) built.setContentText(shown.text)
        return built.build()
    }

    private fun builder(channelId: String, channelName: String): Notification.Builder {
        if (channelNames[channelId] != channelName) {
            // Low importance: shown without sound. Creating it again renames it
            // when the app's language changed.
            notifications.createNotificationChannel(
                NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_LOW),
            )
            channelNames[channelId] = channelName
        }
        // The launcher's own intent, so tapping brings the running app forward.
        val open = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setClass(this, MainActivity::class.java)
        return Notification.Builder(this, channelId)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            // Without this Android holds the notification back for ten seconds.
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE))
    }

    private fun button(action: String, label: String): Notification.Action {
        val press = Intent(this, CameraWifiService::class.java).setAction(action)
        val icon: Icon? = null
        return Notification.Action.Builder(
            icon,
            label,
            PendingIntent.getService(this, 0, press, PendingIntent.FLAG_IMMUTABLE),
        ).build()
    }
}
