package io.jeph.grlab

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `io.jeph.grlab/wifi`: joins the camera access point with a
 * [WifiNetworkSpecifier] request and binds the process to it, so dart:io
 * sockets reach 192.168.0.1 over the camera network rather than mobile data
 * (the camera network has no internet, so Android never makes it the
 * default).
 *
 * Every callback runs on the main looper, the same thread as the method
 * channel, so the request state needs no locking.
 *
 * The first join of a camera network shows Android's approval screen
 * (`NetworkRequestDialogActivity`, full-screen on some OEMs). While it
 * covers the app the join timeout is paused, so a user who is still
 * choosing never has the request pulled away; Android remembers the
 * approval per app, network and security type, and later joins of the same
 * network connect without it.
 */
class WifiChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val channel = MethodChannel(messenger, "io.jeph.grlab/wifi")
    private val main = Handler(Looper.getMainLooper())

    /** The live request; callbacks from any older request are ignored. */
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var pending: MethodChannel.Result? = null
    private var timeout: Runnable? = null
    private var requestedSsid: String? = null
    private var network: Network? = null
    private var timeoutMs = 0L

    /** Whether the activity is resumed; MainActivity reports changes. */
    private var resumed = true

    init {
        channel.setMethodCallHandler(this)
    }

    fun onResume() {
        resumed = true
        // Back from the approval screen (or the user returned to the app):
        // give the pending join its full window from now.
        if (callback != null && pending != null) armTimeout()
    }

    fun onPause() {
        resumed = false
        cancelTimeout()
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        fail("cancelled", "the app closed during the Wi-Fi join")
        release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "join" -> join(call, result)
            "currentSsid" -> result.success(currentSsid())
            "leave" -> {
                fail("cancelled", "left the camera network during the join")
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun join(call: MethodCall, result: MethodChannel.Result) {
        val ssid = call.argument<String>("ssid")
        val passphrase = call.argument<String>("passphrase")
        val security = call.argument<String>("security")
        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong()
        if (ssid == null || passphrase == null || security == null || timeoutMs == null) {
            result.error("invalid", "join needs ssid, passphrase, security and timeoutMs", null)
            return
        }
        // Android rejects specifier requests from apps that are not in the
        // foreground; report that distinctly so it is not taken as the user
        // declining.
        if (!resumed) {
            result.error("background", "the app is not in the foreground", null)
            return
        }
        // Always start from a fresh request: after a loss the old one is gone,
        // and a request the OS still holds may be for another network.
        fail("superseded", "a newer Wi-Fi join replaced this one")
        release()

        val specifier = try {
            WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
                // Transition-mode APs accept SAE, so ask for WPA3 as GR WORLD
                // does; GrSession falls back to WPA2 if that fails.
                if (security == "wpa2") setWpa2Passphrase(passphrase) else setWpa3Passphrase(passphrase)
            }.build()
        } catch (e: IllegalArgumentException) {
            result.error("invalid", "Android rejected the camera network: ${e.message}", null)
            return
        }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            // Android refuses specifier requests that also require internet.
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                if (callback !== this) return
                network = n
                if (!connectivity.bindProcessToNetwork(n)) {
                    fail("failed", "Android would not route traffic over \"$ssid\"")
                    release()
                    return
                }
                cancelTimeout()
                pending?.success(null)
                pending = null
            }

            override fun onUnavailable() {
                if (callback !== this) return
                // Without a framework timeout this means the user dismissed
                // the "connect to device" dialog, or Android gave up after
                // repeated association failures (e.g. wrong passphrase).
                fail(
                    "declined",
                    "Android did not connect to \"$ssid\": the system dialog was " +
                        "declined or the connection failed",
                )
                release()
            }

            override fun onLost(n: Network) {
                if (callback !== this || n != network) return
                // Unbind at once so sockets fail fast and the rest of the app
                // regains the default network; GrSession's liveness probe
                // notices and its recovery joins again with a new request.
                release()
            }
        }

        callback = cb
        pending = result
        requestedSsid = ssid
        this.timeoutMs = timeoutMs
        try {
            connectivity.requestNetwork(request, cb, main)
        } catch (e: RuntimeException) {
            // SecurityException for a missing permission, or too many
            // outstanding requests.
            callback = null
            fail("failed", "Android refused the Wi-Fi request: ${e.message}")
            release()
            return
        }
        if (resumed) armTimeout()
    }

    private fun armTimeout() {
        cancelTimeout()
        val cb = callback ?: return
        val ssid = requestedSsid
        val ms = timeoutMs
        val onTimeout = Runnable {
            if (callback === cb) {
                fail("timeout", "\"$ssid\" did not connect within $ms ms")
                release()
            }
        }
        timeout = onTimeout
        main.postDelayed(onTimeout, ms)
    }

    private fun currentSsid(): String? {
        val joined = network
        if (joined != null) return visibleSsid(joined) ?: requestedSsid
        return connectivity.activeNetwork?.let(::visibleSsid)
    }

    /** Android redacts SSIDs without location access; then this is null. */
    private fun visibleSsid(n: Network): String? {
        val info = connectivity.getNetworkCapabilities(n)?.transportInfo as? WifiInfo ?: return null
        val ssid = info.ssid ?: return null
        if (ssid == WifiManager.UNKNOWN_SSID) return null
        return ssid.removeSurrounding("\"")
    }

    private fun fail(code: String, message: String) {
        pending?.error(code, message, null)
        pending = null
    }

    private fun cancelTimeout() {
        timeout?.let(main::removeCallbacks)
        timeout = null
    }

    /** Drops the request and the process binding; [pending] must be settled first. */
    private fun release() {
        cancelTimeout()
        callback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (ignored: IllegalArgumentException) {
                // Never registered (requestNetwork threw) or already gone.
            }
        }
        callback = null
        val joined = network
        if (joined != null && connectivity.boundNetworkForProcess == joined) {
            connectivity.bindProcessToNetwork(null)
        }
        network = null
        requestedSsid = null
    }
}
