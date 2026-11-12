package io.jeph.grphoto.gr_camera

import android.Manifest
import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.IBinder

/** The texts of the geotagging notification, in the app's language. */
data class GeotagNotice(
    val title: String,
    val text: String,
    val stopLabel: String,
    val channelName: String,
)

/**
 * The foreground service of a geotagging run: what lets [LocationChannel]
 * go on receiving the phone's position, and the app's Dart code go on
 * writing it to the camera, while the app is not in front. Its type is
 * `location`, which carries the app's while-in-use location access into
 * the background; Android only lets such a service start while the app is
 * in front.
 *
 * The service holds nothing but the notification. The location updates and
 * the wake lock belong to [LocationChannel], which registers itself as
 * [host], starts and stops the service, and is told here when the service
 * came up, could not, was destroyed, or had its Stop action pressed.
 * Everything runs on the main thread.
 */
class GeotagService : Service() {
    /** The [LocationChannel] side of a run. */
    interface Host {
        /**
         * The service is in the foreground. False when no run wants it
         * any more (stopped while the service was still coming up).
         */
        fun onServiceStarted(): Boolean

        /** Android refused the foreground start; [code] is the channel's error code. */
        fun onServiceStartFailed(code: String, message: String)

        /** The notification's Stop action was pressed. */
        fun onStopAction()

        fun onServiceDestroyed()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val current = host
        if (intent?.action == ACTION_STOP) {
            // The host ends its run, which stops this service; without a
            // host or a run nothing else would.
            current?.onStopAction()
            stopSelf()
            return START_NOT_STICKY
        }
        val notice = intent?.let(::noticeOf)
        if (notice == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Whatever the host says afterwards, go to the foreground first:
        // Android crashes an app whose startForegroundService is not
        // followed by startForeground.
        try {
            startForeground(
                NOTIFICATION_ID,
                notification(this, notice),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } catch (e: ForegroundServiceStartNotAllowedException) {
            current?.onServiceStartFailed("background", "Android refused the service: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        } catch (e: SecurityException) {
            // Android 14 and later: a location service needs a location
            // permission, and the app in a state where it may use it,
            // which in the background it is not.
            val code = if (hasLocationPermission(this)) "background" else "denied"
            current?.onServiceStartFailed(code, "Android refused the service: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        if (current?.onServiceStarted() != true) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        host?.onServiceDestroyed()
        super.onDestroy()
    }

    companion object {
        /** The channel of the attached engine; null while there is none. */
        var host: Host? = null

        /** The intent that starts the service showing [notice]. */
        fun startIntent(context: Context, notice: GeotagNotice): Intent =
            Intent(context, GeotagService::class.java)
                .putExtra(EXTRA_TITLE, notice.title)
                .putExtra(EXTRA_TEXT, notice.text)
                .putExtra(EXTRA_STOP_LABEL, notice.stopLabel)
                .putExtra(EXTRA_CHANNEL_NAME, notice.channelName)

        fun intent(context: Context): Intent = Intent(context, GeotagService::class.java)

        /**
         * Replaces the notification of the running service with [notice].
         * Only while the service is in the foreground: otherwise this
         * would post a notification nothing takes down.
         */
        fun update(context: Context, notice: GeotagNotice) {
            context.getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification(context, notice))
        }

        fun hasLocationPermission(context: Context): Boolean =
            granted(context, Manifest.permission.ACCESS_FINE_LOCATION) ||
                granted(context, Manifest.permission.ACCESS_COARSE_LOCATION)

        fun granted(context: Context, permission: String): Boolean =
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

        private fun noticeOf(intent: Intent): GeotagNotice? {
            return GeotagNotice(
                title = intent.getStringExtra(EXTRA_TITLE) ?: return null,
                text = intent.getStringExtra(EXTRA_TEXT) ?: return null,
                stopLabel = intent.getStringExtra(EXTRA_STOP_LABEL) ?: return null,
                channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: return null,
            )
        }

        private fun notification(context: Context, notice: GeotagNotice): Notification {
            // Creating a channel that exists only renames it, which is how
            // a change of the app's language reaches the system settings.
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, notice.channelName, NotificationManager.IMPORTANCE_LOW),
            )
            val icon = Icon.createWithResource(context, R.drawable.ic_stat_geotag)
            val stop = PendingIntent.getService(
                context,
                0,
                intent(context).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(icon)
                .setContentTitle(notice.title)
                .setContentText(notice.text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                // Shown at once: Android otherwise holds a service's
                // notification back for ten seconds.
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                .addAction(Notification.Action.Builder(icon, notice.stopLabel, stop).build())
            // The launch intent brings the app's task to the front as the
            // launcher icon does.
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { open ->
                builder.setContentIntent(
                    PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE),
                )
            }
            return builder.build()
        }

        private const val CHANNEL_ID = "geotagging"

        /** The app's download notification is 1. */
        private const val NOTIFICATION_ID = 2
        private const val ACTION_STOP = "io.jeph.grphoto.geotag.STOP"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_STOP_LABEL = "stopLabel"
        private const val EXTRA_CHANNEL_NAME = "channelName"
    }
}
