package io.jeph.grlab

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `io.jeph.grlab/downloads`: `show` puts the download queue up as
 * [DownloadService]'s notification and `hide` takes it down; the
 * notification's buttons come back as `action` with `pause`, `resume` or
 * `cancel`.
 *
 * The first `show` with the app in front asks for the notification
 * permission (Android 13 and later), once per launch. Refused, the service
 * still runs and Android lists it under its active apps, without the
 * notification.
 */
class DownloadChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private companion object {
        const val NOTIFICATION_REQUEST = 1
    }

    private val channel = MethodChannel(messenger, "io.jeph.grlab/downloads")
    private var askedToNotify = false

    init {
        channel.setMethodCallHandler(this)
        DownloadService.onAction = { channel.invokeMethod("action", it) }
    }

    /** The Dart side is gone, and the downloads with it. */
    fun dispose() {
        channel.setMethodCallHandler(null)
        DownloadService.onAction = null
        DownloadService.hide()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> show(call, result)
            "hide" -> {
                DownloadService.hide()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(call: MethodCall, result: MethodChannel.Result) {
        val status = status(call)
        if (status == null) {
            result.error("failed", "show needs paused, title, detail, camera, fraction, toggle, cancel and channel", null)
            return
        }
        askToNotify()
        try {
            DownloadService.show(activity, status)
            result.success(null)
        } catch (e: IllegalStateException) {
            // The app went to the background before its downloads started;
            // the next status tries again.
            result.error("notStarted", "Android did not start the download service: ${e.message}", null)
        }
    }

    private fun status(call: MethodCall): DownloadService.Status? {
        return DownloadService.Status(
            paused = call.argument<Boolean>("paused") ?: return null,
            title = call.argument<String>("title") ?: return null,
            detail = call.argument<String>("detail") ?: return null,
            camera = call.argument<String>("camera") ?: return null,
            fraction = call.argument<Double>("fraction") ?: return null,
            toggle = call.argument<String>("toggle") ?: return null,
            cancel = call.argument<String>("cancel") ?: return null,
            channel = call.argument<String>("channel") ?: return null,
        )
    }

    private fun askToNotify() {
        if (askedToNotify || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        // Android only shows the question over an app that is in front.
        if (!activity.hasWindowFocus()) return
        askedToNotify = true
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return
        activity.requestPermissions(arrayOf(permission), NOTIFICATION_REQUEST)
    }
}
