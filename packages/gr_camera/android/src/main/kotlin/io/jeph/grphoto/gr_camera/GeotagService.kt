package io.jeph.grphoto.gr_camera

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock

/**
 * Keeps GR Photo running while live geotagging runs or waits for the
 * camera with the app not in front, and shows that as a notification with
 * a Stop button.
 *
 * A foreground service is what keeps Android from freezing the process,
 * and with it the Bluetooth link to the camera, and what lets the app be
 * located with its screen off. Its types are `location` and
 * `connectedDevice` (the camera, over Bluetooth). The service does no work
 * itself: the Dart side locates the phone and writes to the camera, says
 * what to show ([hold]) and when it is done ([release]).
 *
 * Only the Dart side starts it, by holding a run ([hold], the channel's
 * `holdRun`), so it never runs without a Flutter engine.
 *
 * While the run is `awake` (a camera is on) the service holds a partial
 * wake lock, so the Dart side's timers run with the screen off; a run that
 * only waits holds none. The lock is timed and renewed by what the Dart
 * side does while it works (a held run updated, a position passed on or
 * asked for, [alive]), so it runs out by itself [WAKE_LOCK_TIMEOUT_MS]
 * after the Dart side stopped working.
 *
 * Everything here runs on the main thread.
 */
class GeotagService : Service() {
    /** The notification's texts, in the user's language; [channel] names its channel. */
    internal data class Notice(
        val title: String,
        val text: String,
        val stopLabel: String,
        val channel: String,
    )

    /** Why a run could not be held: a `holdRun` error code and Android's message. */
    internal class Failure(val code: String, val message: String)

    internal companion object {
        private const val CHANNEL_ID = "geotagging"

        // The app's download notification is 1; ids are shared by the app.
        private const val NOTIFICATION_ID = 2
        private const val ACTION_STOP = "io.jeph.grphoto.gr_camera.GEOTAG_STOP"
        private const val WAKE_LOCK_TIMEOUT_MS = 10 * 60 * 1000L

        /** A lock renewed less than this long ago is left alone. */
        private const val RENEW_AFTER_MS = 60 * 1000L

        /** Called when the user pressed Stop; the run is released already. */
        var onStopped: (() -> Unit)? = null

        private val main = Handler(Looper.getMainLooper())
        private var notice: Notice? = null
        private var awake = false

        /**
         * The Dart side holds a run: the service runs or is starting. See
         * [GeotagHost.runHeld].
         */
        var held = false
            private set

        /** `startForegroundService` was called and `onStartCommand` is due. */
        private var starting = false
        private var running: GeotagService? = null

        /** The `holdRun` calls waiting for the service to start. */
        private val waiting = mutableListOf<(Failure?) -> Unit>()

        /**
         * Holds a run showing [next], or updates the one held. [done] gets
         * null once the service is in the foreground, or why it is not.
         */
        fun hold(context: Context, next: Notice, keepAwake: Boolean, done: (Failure?) -> Unit) {
            notice = next
            awake = keepAwake
            held = true
            val service = running
            if (service != null) {
                service.show(next)
                done(null)
                return
            }
            waiting += done
            if (starting) return
            try {
                context.startForegroundService(Intent(context, GeotagService::class.java))
                starting = true
            } catch (e: ForegroundServiceStartNotAllowedException) {
                held = false
                settle(Failure("background", "Android does not start the run in the background: ${e.message}"))
            } catch (e: RuntimeException) {
                held = false
                settle(Failure("failed", "Android did not start the run: ${e.message}"))
            }
        }

        /** Ends the run the Dart side holds; nothing happens without one. */
        fun release() {
            if (held) end()
        }

        /**
         * The app is on screen again: asks for both service types once
         * more, for a service that Android started without the `location`
         * type or without location access (see [enterForeground]).
         */
        fun refresh() {
            val service = running ?: return
            val shown = notice ?: return
            if (!held) return
            val failure = service.enterForeground(shown) ?: return
            service.log("the run could not be renewed in the foreground: ${failure.message}")
        }

        /**
         * The Dart side is at work (a position passed on or asked for):
         * renews the wake lock of an awake run.
         */
        fun alive() {
            val service = running ?: return
            if (!awake || SystemClock.elapsedRealtime() - service.renewedAt < RENEW_AFTER_MS) return
            service.keepAwake()
        }

        /** Ends the run and the service, and tells the host. */
        private fun end() {
            held = false
            // A service still starting stops when it arrives.
            settle(null)
            running?.stop()
            ended()
        }

        /** Posted, so the host never ends an engine from inside one of its calls. */
        private fun ended() {
            main.post { GeotagHost.runEnded?.invoke() }
        }

        private fun settle(failure: Failure?) {
            val callbacks = waiting.toList()
            waiting.clear()
            for (done in callbacks) done(failure)
        }
    }

    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private val wakeLock by lazy {
        getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "grphoto:geotagging")
            .apply { setReferenceCounted(false) }
    }
    private var channelName: String? = null

    /** When the wake lock was last taken, on the clock of [SystemClock.elapsedRealtime]. */
    private var renewedAt = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // The notification's button, sent with startService: it owes
            // Android no startForeground.
            if (held) stoppedByUser() else stopSelf()
            return START_NOT_STICKY
        }
        starting = false
        val shown = notice
        if (shown == null) {
            // Every start sets a notice first (hold), and the service is
            // not restarted by Android (START_NOT_STICKY).
            stopSelf()
            return START_NOT_STICKY
        }
        // Android requires this of a service started with
        // startForegroundService, even one that is to stop at once.
        val failure = enterForeground(shown)
        if (failure != null) {
            log("not started: ${failure.code}: ${failure.message}")
            held = false
            settle(failure)
            stopSelf()
            return START_NOT_STICKY
        }
        running = this
        if (!held) {
            // Released while it was starting.
            stop()
            return START_NOT_STICKY
        }
        keepAwake()
        settle(null)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (running === this) running = null
        super.onDestroy()
    }

    /**
     * Puts the service in the foreground with [shown] as both a location
     * and a connected-device service, or as a connected-device service
     * alone when Android refuses the location type.
     *
     * Android 14 and later refuse it with a [SecurityException] when the
     * service starts while the app is in the background and location is
     * allowed only while the app is in use: there, the permission does not
     * count in the background (developer.android.com/develop/background-work/services/fgs/restrictions-bg-start,
     * "Restrictions on starting foreground services that need while-in-use
     * permissions"; it needs "Allow all the time"). That is the case when
     * the Dart side, still running in the background with no run held,
     * links a camera and holds one. The connected-device type alone keeps the
     * process and the camera link going, though without positions, until
     * the app is next on screen and [refresh] asks for both types again.
     * Earlier versions accept both types and withhold the positions
     * instead, which [refresh] also ends.
     */
    private fun enterForeground(shown: Notice): Failure? = try {
        val built = notification(shown)
        try {
            startForeground(
                NOTIFICATION_ID,
                built,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } catch (e: SecurityException) {
            log("Android refused the location service type (${e.message}); running as a connected-device service")
            startForeground(NOTIFICATION_ID, built, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        }
        null
    } catch (e: ForegroundServiceStartNotAllowedException) {
        Failure("background", "Android does not start the run in the background: ${e.message}")
    } catch (e: RuntimeException) {
        Failure("failed", "Android did not start the run: ${e.message}")
    }

    private fun stoppedByUser() {
        log("stopped from the notification")
        end()
        onStopped?.invoke()
    }

    private fun show(next: Notice) {
        notifications.notify(NOTIFICATION_ID, notification(next))
        keepAwake()
    }

    private fun stop() {
        // A run held after this starts the service anew.
        running = null
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun keepAwake() {
        if (!awake) {
            releaseWakeLock()
            return
        }
        wakeLock.acquire(WAKE_LOCK_TIMEOUT_MS)
        renewedAt = SystemClock.elapsedRealtime()
    }

    private fun releaseWakeLock() {
        if (wakeLock.isHeld) wakeLock.release()
    }

    private fun notification(shown: Notice): Notification {
        if (channelName != shown.channel) {
            // Low importance: shown without sound. Creating it again renames it
            // when the app's language changed.
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, shown.channel, NotificationManager.IMPORTANCE_LOW),
            )
            channelName = shown.channel
        }
        val press = Intent(this, GeotagService::class.java).setAction(ACTION_STOP)
        val icon: Icon? = null
        val stop = Notification.Action.Builder(
            icon,
            shown.stopLabel,
            PendingIntent.getService(this, 0, press, PendingIntent.FLAG_IMMUTABLE),
        ).build()
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_geotag)
            .setContentTitle(shown.title)
            .setContentText(shown.text)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            // Without this Android holds the notification back for ten seconds.
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(stop)
        // The launcher's own intent, so tapping brings the running app forward.
        val open = packageManager.getLaunchIntentForPackage(packageName)
        if (open != null) {
            builder.setContentIntent(PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE))
        }
        return builder.build()
    }

    private fun log(message: String) = Logs.location.log(this, "run: $message")
}
