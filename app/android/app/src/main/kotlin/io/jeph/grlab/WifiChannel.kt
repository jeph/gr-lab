package io.jeph.grlab

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkInfo
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
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
 * network connect without it. Android shows the screen again despite that
 * approval after the network was disconnected by hand in Wi-Fi settings
 * (`WifiNetworkFactory`: user-disabled networks skip the bypass), so the
 * app is told whenever the screen covers a join (`approvalShown`) and a
 * toast names the network to choose.
 *
 * For a camera approved before, Android connects as soon as one of its
 * scans sees the camera network, but it scans when a request arrives and
 * then only every ~17.5 s (Android 17, 2026-11-08; AOSP
 * says 10 s), while the camera's access point comes up a variable time
 * after WLAN-on. So the request is repeated every [RESCAN_MS], each time
 * starting a scan, until Android starts connecting. That start is seen in
 * the primary Wi-Fi state broadcasts, which fire whether the phone was on
 * another Wi-Fi network or on mobile data: while the state moves, no new
 * request is made. The broadcasts do not say which network moved (that
 * needs location access), and right after leaving a camera the phone
 * rejoins its usual network: so when the phone ends up connected and the
 * request is still open [OTHER_NETWORK_MS] later, the connection was to
 * another network and the requests go on (seen 2026-11-08: an 18 s wait
 * while the phone rejoined home Wi-Fi). Phones that join the camera on a
 * second, concurrent Wi-Fi interface get no such broadcast, so there the
 * request is never repeated. Neither is it while Android's approval
 * screen is up.
 */
class WifiChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val channel = MethodChannel(messenger, "io.jeph.grlab/wifi")
    private val main = Handler(Looper.getMainLooper())

    /** The live request; callbacks from any older request are ignored. */
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var request: NetworkRequest? = null
    private var pending: MethodChannel.Result? = null
    private var timeout: Runnable? = null
    private var requestedSsid: String? = null
    private var network: Network? = null
    private var timeoutMs = 0L

    /** Counts joins, so a timeout only ends the join that armed it. */
    private var joinId = 0

    private var rescan: Runnable? = null
    private var stateReceiver: BroadcastReceiver? = null
    private var requests = 0

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
        stopRescans()
        // A join in progress loses the foreground to Android's network
        // screen (or, rarely, to the user leaving the app).
        val ssid = requestedSsid
        if (callback != null && pending != null && ssid != null) {
            channel.invokeMethod("approvalShown", null)
            Toast.makeText(
                context,
                "Choose \"$ssid\" to connect your camera",
                Toast.LENGTH_LONG,
            ).show()
        }
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
        val approved = call.argument<Boolean>("approved") ?: false
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

        joinId++
        this.request = request
        pending = result
        requestedSsid = ssid
        this.timeoutMs = timeoutMs
        requests = 0
        if (!requestNetwork()) return
        if (resumed) armTimeout()
        val wifi = context.getSystemService(WifiManager::class.java)
        if (approved && !wifi.isStaConcurrencyForLocalOnlyConnectionsSupported) startRescans()
    }

    /** Files [request] with a new callback; false when Android refused it. */
    private fun requestNetwork(): Boolean {
        val request = request ?: return false
        val ssid = requestedSsid
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                if (callback !== this) return
                stopRescans()
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
                // regains the default network, then tell Dart: the session
                // ends the Wi-Fi link without waiting for its liveness probe.
                // Runs on the main looper (requestNetwork's handler).
                release()
                channel.invokeMethod("lost", null)
            }
        }

        unregisterCallback()
        callback = cb
        requests++
        try {
            connectivity.requestNetwork(request, cb, main)
        } catch (e: RuntimeException) {
            // SecurityException for a missing permission, or too many
            // outstanding requests.
            callback = null
            fail("failed", "Android refused the Wi-Fi request: ${e.message}")
            release()
            return false
        }
        return true
    }

    /**
     * Repeats the request every [RESCAN_MS], holding off while the Wi-Fi
     * state moves (see the class comment).
     */
    private fun startRescans() {
        val tick = object : Runnable {
            override fun run() {
                if (rescan !== this || pending == null || !resumed) return
                Log.i(TAG, "\"$requestedSsid\" not found yet; request ${requests + 1}")
                if (!requestNetwork()) return
                main.postDelayed(this, RESCAN_MS)
            }
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                // Registering delivers the last (sticky) state at once; only
                // changes after the request count.
                if (isInitialStickyBroadcast || rescan !== tick) return
                main.removeCallbacks(tick)
                // NetworkInfo is deprecated, but it is the documented payload
                // of NETWORK_STATE_CHANGED_ACTION; the typed getter needs API 33.
                @Suppress("DEPRECATION")
                val state = intent.getParcelableExtra<NetworkInfo>(
                    WifiManager.EXTRA_NETWORK_INFO,
                )?.detailedState
                @Suppress("DEPRECATION")
                when (state) {
                    NetworkInfo.DetailedState.CONNECTED -> {
                        Log.i(TAG, "Wi-Fi connected after request $requests; is it the camera?")
                        main.postDelayed(tick, OTHER_NETWORK_MS)
                    }
                    // Settled off any network: nothing is joining, unless a
                    // later broadcast says otherwise.
                    NetworkInfo.DetailedState.DISCONNECTED -> main.postDelayed(tick, RESCAN_MS)
                    else -> Log.i(TAG, "Wi-Fi state $state after request $requests; holding")
                }
            }
        }
        stateReceiver = receiver
        context.registerReceiver(
            receiver,
            IntentFilter(WifiManager.NETWORK_STATE_CHANGED_ACTION),
            Context.RECEIVER_NOT_EXPORTED,
        )
        rescan = tick
        main.postDelayed(tick, RESCAN_MS)
    }

    private fun stopRescans() {
        rescan?.let(main::removeCallbacks)
        rescan = null
        stateReceiver?.let {
            stateReceiver = null
            context.unregisterReceiver(it)
        }
    }

    private fun armTimeout() {
        cancelTimeout()
        if (callback == null) return
        val id = joinId
        val ssid = requestedSsid
        val ms = timeoutMs
        val onTimeout = Runnable {
            if (id == joinId && pending != null) {
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

    private fun unregisterCallback() {
        callback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (ignored: IllegalArgumentException) {
                // Never registered (requestNetwork threw) or already gone.
            }
        }
        callback = null
    }

    /** Drops the request and the process binding; [pending] must be settled first. */
    private fun release() {
        cancelTimeout()
        stopRescans()
        unregisterCallback()
        request = null
        val joined = network
        if (joined != null && connectivity.boundNetworkForProcess == joined) {
            connectivity.bindProcessToNetwork(null)
        }
        network = null
        requestedSsid = null
    }
}

/** Longer than the camera network takes to reach [WifiChannel] once connected (~20 ms seen). */
private const val OTHER_NETWORK_MS = 2_500L

private const val TAG = "GrLabWifi"

/** Longer than one scan and connect (≤ 4.8 s and ≤ 1.2 s observed). */
private const val RESCAN_MS = 7_000L
