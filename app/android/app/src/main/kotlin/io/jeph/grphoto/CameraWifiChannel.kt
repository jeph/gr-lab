package io.jeph.grphoto

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `io.jeph.grphoto/camera-wifi`: `hold` keeps [CameraWifiService] running
 * for the camera's Wi-Fi, showing `{title, text, camera, disconnect,
 * channel}` while there are no downloads, `keepAwake` keeps the phone
 * awake for `{ms}` (0 for not at all) and `release` lets the service go
 * once the phone has left the Wi-Fi. The notification's Disconnect button
 * comes back as `disconnect`.
 *
 * It asks for no notification permission: refused or not asked, the
 * service still runs, and Android lists it under its active apps without
 * the notification.
 */
class CameraWifiChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "io.jeph.grphoto/camera-wifi")

    init {
        channel.setMethodCallHandler(this)
        CameraWifiService.onDisconnect = { channel.invokeMethod("disconnect", null) }
    }

    /** The Dart side is gone, and its hold of the Wi-Fi with it. */
    fun dispose() {
        channel.setMethodCallHandler(null)
        CameraWifiService.onDisconnect = null
        CameraWifiService.releaseWifi()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hold" -> hold(call, result)
            "keepAwake" -> {
                val ms = call.argument<Number>("ms")?.toLong()
                if (ms == null) {
                    result.error("failed", "keepAwake needs ms", null)
                    return
                }
                CameraWifiService.keepAwakeFor(ms)
                result.success(null)
            }
            "release" -> {
                CameraWifiService.releaseWifi()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hold(call: MethodCall, result: MethodChannel.Result) {
        val notice = CameraWifiService.Wifi(
            title = call.argument<String>("title") ?: return missing(result),
            text = call.argument<String>("text") ?: return missing(result),
            camera = call.argument<String>("camera") ?: return missing(result),
            disconnect = call.argument<String>("disconnect") ?: return missing(result),
            channel = call.argument<String>("channel") ?: return missing(result),
        )
        try {
            CameraWifiService.holdWifi(context, notice)
            result.success(null)
        } catch (e: IllegalStateException) {
            // Android starts the service only for an app in front.
            result.error("notStarted", "Android did not start the service: ${e.message}", null)
        }
    }

    private fun missing(result: MethodChannel.Result) =
        result.error("failed", "hold needs title, text, camera, disconnect and channel", null)
}
