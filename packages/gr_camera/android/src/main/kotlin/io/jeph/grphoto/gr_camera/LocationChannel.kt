package io.jeph.grphoto.gr_camera

import android.Manifest
import android.app.Activity
import android.app.ForegroundServiceStartNotAllowedException
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.LocationRequest
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `io.jeph.grphoto/location`: the phone's own position, read to geotag a
 * camera's pictures.
 *
 * A run (`start` to `stop`) holds [GeotagService] in the foreground, which
 * is what lets positions arrive, and the Dart code write them to the
 * camera, while the app is not in front. During a run `setMode` says
 * whether a camera wants positions now: in `precise` the phone is asked
 * for one every interval, in `idle` for none, so a run that waits for a
 * camera does not keep the phone's GPS on.
 *
 * Positions come from [LocationManager], on the fused provider when the
 * phone has one and on GPS otherwise, as GR WORLD's do
 * (research/protocol/geotagging.md §2.1); that needs no Google Play
 * services library.
 *
 * Every callback runs on the main thread, the same as the method channel
 * and [GeotagService], so the run's state needs no locking.
 *
 * Every log line also goes to Dart (`log`), which records it in the
 * camera trace.
 */
class LocationChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, GeotagService.Host {
    private val locations = context.getSystemService(LocationManager::class.java)
    private val channel = MethodChannel(messenger, "io.jeph.grphoto/location")

    /**
     * The activity this engine is attached to, which Android's permission
     * prompt needs; [GrCameraPlugin] keeps it current.
     */
    var activity: Activity? = null

    /** `requestAccess` calls waiting for the answer to one prompt. */
    private val accessRequests = mutableListOf<MethodChannel.Result>()

    /** `start` calls waiting for [GeotagService] to reach the foreground. */
    private val startRequests = mutableListOf<MethodChannel.Result>()

    /** The service was asked to start and has not answered. */
    private var starting = false

    /** A run is under way: the service is in the foreground. */
    private var running = false

    /** The run is in precise mode: location updates are requested. */
    private var precise = false

    /** What the latest `start` asked for. */
    private var notice: GeotagNotice? = null
    private var intervalMs = 0L

    /** What the service's notification shows. */
    private var shownNotice: GeotagNotice? = null

    /**
     * Held for the whole run \[design\]: the run's Dart code (relinking
     * the camera, writing positions to it) has to run with the screen
     * off, and a foreground service alone does not keep the processor on.
     * GR WORLD holds one for its whole location run too
     * (research/protocol/geotagging.md §2.1). It has no timeout because
     * the run is bounded by the camera layer, which stops it; the lock is
     * released wherever the run ends.
     */
    private val wakeLock = context.getSystemService(PowerManager::class.java)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GrPhoto:geotag")
        .apply { setReferenceCounted(false) }

    /** Set by [dispose]; Dart is no longer listening. */
    private var disposed = false

    /** Android was asked, once since the app started, to allow notifications. */
    private var askedToNotify = false

    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) = onFix(location)

        override fun onProviderDisabled(provider: String) = onProviderChanged(provider, "disabled")

        override fun onProviderEnabled(provider: String) = onProviderChanged(provider, "enabled")
    }

    init {
        channel.setMethodCallHandler(this)
        GeotagService.host = this
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        activity = null
        val answer = access()
        accessRequests.forEach { it.success(answer) }
        accessRequests.clear()
        // A service still coming up finds no host and stops itself.
        starting = false
        failStart("cancelled", "the app closed while the geotagging service started")
        if (running) endRun()
        if (GeotagService.host === this) GeotagService.host = null
    }

    /**
     * The app's "Enable debug logging" setting, sent through `setLogging`
     * when the engine starts and whenever it changes.
     */
    @Volatile
    private var nativeLogging = false

    /**
     * Logs [message] to logcat and, while the engine is attached, to Dart;
     * nothing while [nativeLogging] is off.
     */
    private fun log(message: String) {
        if (!nativeLogging) return
        Log.i(TAG, message)
        if (!disposed) channel.invokeMethod("log", message)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "access" -> result.success(access())
            "requestAccess" -> requestAccess(result)
            "openSettings" -> openSettings(result)
            "start" -> start(call, result)
            "setMode" -> setMode(call.arguments as? String, result)
            "stop" -> {
                stop()
                result.success(null)
            }
            "setLogging" -> {
                nativeLogging = call.arguments as? Boolean ?: false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * What the phone allows now. Never `blocked`: Android only reveals
     * that it will not ask again in the answer to a request
     * ([onRequestPermissionsResult]).
     */
    private fun access(): String {
        val fine = GeotagService.granted(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = GeotagService.granted(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        return when {
            !fine && !coarse -> "undetermined"
            !locations.isLocationEnabled -> "off"
            fine -> "precise"
            else -> "approximate"
        }
    }

    private fun requestAccess(result: MethodChannel.Result) {
        val a = activity
        // With approximate access only, asking again lets the user turn
        // on precise.
        if (a == null || GeotagService.granted(context, Manifest.permission.ACCESS_FINE_LOCATION)) {
            result.success(access())
            return
        }
        accessRequests += result
        if (accessRequests.size > 1) return
        log("asking Android for location access")
        // Precise can only be asked for together with approximate.
        a.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            PERMISSION_REQUEST,
        )
    }

    /**
     * The answer to [requestAccess]'s prompt, from [GrCameraPlugin]; false
     * for another request's.
     */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode == NOTIFICATION_REQUEST) {
            log("notifications after asking: results ${grantResults.joinToString()}")
            // Android dropped the notice the service posted before the
            // user allowed notifications, and shows it only when it is
            // posted again (seen on an Android 16 emulator, 2026-11-12).
            val shown = shownNotice
            if (running && shown != null) GeotagService.update(context, shown)
            return true
        }
        if (requestCode != PERMISSION_REQUEST) return false
        var answer = access()
        // Refused, and Android offers no rationale for either permission:
        // it will not show the prompt again. Empty results mean the prompt
        // was interrupted, not answered.
        val a = activity
        if (answer == "undetermined" && grantResults.isNotEmpty() && a != null &&
            !a.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) &&
            !a.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION)
        ) {
            answer = "blocked"
        }
        log("location access after asking: $answer (results ${grantResults.joinToString()})")
        accessRequests.forEach { it.success(answer) }
        accessRequests.clear()
        return true
    }

    /**
     * Asks Android, once since the app started, to let the run's
     * notification show: without it the run goes on unseen, with its Stop
     * button only in Android's list of active apps. Android shows the
     * question only over an app that is in front.
     */
    private fun askToNotify() {
        val a = activity
        if (askedToNotify || a == null || !a.hasWindowFocus()) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        askedToNotify = true
        if (GeotagService.granted(context, Manifest.permission.POST_NOTIFICATIONS)) return
        log("asking Android to allow notifications")
        a.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    private fun openSettings(result: MethodChannel.Result) {
        // The phone's location switch only when it is what stands in the
        // way: without a permission the app's own page comes first, as
        // `access` answers `undetermined` then, not `off`.
        val intent = if (access() == "off") {
            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null),
            )
        }
        log("opening ${intent.action}")
        try {
            val a = activity
            if (a != null) {
                a.startActivity(intent)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        } catch (e: ActivityNotFoundException) {
            result.error("failed", "this phone has no such settings screen: ${e.message}", null)
            return
        }
        result.success(null)
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title")
        val text = call.argument<String>("text")
        val stopLabel = call.argument<String>("stopLabel")
        val channelName = call.argument<String>("channelName")
        val intervalMs = call.argument<Number>("intervalMs")?.toLong()
        if (title == null || text == null || stopLabel == null || channelName == null ||
            intervalMs == null || intervalMs <= 0
        ) {
            result.error(
                "invalid",
                "start needs title, text, stopLabel, channelName and a positive intervalMs",
                null,
            )
            return
        }
        if (!GeotagService.hasLocationPermission(context)) {
            result.error("denied", "no location permission is granted", null)
            return
        }
        val next = GeotagNotice(title, text, stopLabel, channelName)
        notice = next
        val intervalChanged = intervalMs != this.intervalMs
        this.intervalMs = intervalMs
        if (running) {
            log("run under way; interval $intervalMs ms, notice $next")
            showNotice()
            if (precise && intervalChanged && !requestUpdates(result)) return
            result.success(null)
            return
        }
        startRequests += result
        if (starting) return
        askToNotify()
        log("starting the geotagging service; interval $intervalMs ms, notice $next")
        try {
            context.startForegroundService(GeotagService.startIntent(context, next))
        } catch (e: ForegroundServiceStartNotAllowedException) {
            failStart("background", "Android refused the service: ${e.message}")
            return
        }
        shownNotice = next
        starting = true
    }

    override fun onServiceStarted(): Boolean {
        // A second start command to a service this run already holds.
        if (!starting) return running
        starting = false
        running = true
        precise = false
        wakeLock.acquire()
        log("geotagging service in the foreground; wake lock held")
        // A start that arrived while the service came up changed the texts.
        showNotice()
        startRequests.forEach { it.success(null) }
        startRequests.clear()
        return true
    }

    override fun onServiceStartFailed(code: String, message: String) {
        if (!starting) return
        starting = false
        failStart(code, message)
    }

    override fun onStopAction() {
        if (!running) return
        log("Stop pressed on the notification")
        endRun()
        if (!disposed) channel.invokeMethod("stopRequested", null)
    }

    override fun onServiceDestroyed() {
        // Not running: this channel stopped the service itself.
        if (!running) return
        // Android took the service down (the task was swiped away).
        log("geotagging service destroyed during a run")
        endRun()
        if (!disposed) channel.invokeMethod("stopRequested", null)
    }

    private fun setMode(mode: String?, result: MethodChannel.Result) {
        if (mode != "precise" && mode != "idle") {
            result.error("invalid", "setMode needs \"precise\" or \"idle\"", null)
            return
        }
        if (!running) {
            result.error("notRunning", "no geotagging run is under way", null)
            return
        }
        if (mode == "idle") {
            removeUpdates()
            result.success(null)
            return
        }
        if (!requestUpdates(result)) return
        result.success(null)
    }

    private fun stop() {
        if (starting) {
            // The service is still coming up; it stops itself when
            // onServiceStarted tells it no run wants it.
            starting = false
            failStart("cancelled", "the run was stopped while the geotagging service started")
        }
        if (running) endRun()
    }

    /**
     * Asks for a position every [intervalMs], replacing any earlier
     * request. On failure answers [result] with the error and returns
     * false.
     */
    private fun requestUpdates(result: MethodChannel.Result): Boolean {
        val provider = if (LocationManager.FUSED_PROVIDER in locations.allProviders) {
            LocationManager.FUSED_PROVIDER
        } else {
            LocationManager.GPS_PROVIDER
        }
        val request = LocationRequest.Builder(intervalMs)
            .setQuality(LocationRequest.QUALITY_HIGH_ACCURACY)
            .setMinUpdateIntervalMillis(intervalMs)
            .setMinUpdateDistanceMeters(0f)
            // No batching: each position is delivered as it is found.
            .setMaxUpdateDelayMillis(0)
            .build()
        try {
            locations.requestLocationUpdates(provider, request, context.mainExecutor, listener)
        } catch (e: SecurityException) {
            // The GPS provider takes precise access only.
            removeUpdates()
            log("location updates from $provider refused: ${e.message}")
            result.error("denied", "Android refused location updates: ${e.message}", null)
            return false
        } catch (e: IllegalArgumentException) {
            // A phone with neither a fused nor a GPS provider.
            removeUpdates()
            log("no location provider: ${e.message}")
            result.error("failed", "this phone has no $provider location provider", null)
            return false
        }
        precise = true
        log("location updates from $provider every $intervalMs ms")
        return true
    }

    private fun removeUpdates() {
        if (!precise) return
        precise = false
        locations.removeUpdates(listener)
        log("location updates removed")
    }

    private fun onFix(location: Location) {
        if (!running || !precise || disposed) return
        // A position without an accuracy cannot be judged.
        if (!location.hasAccuracy()) {
            log("position from ${location.provider} without accuracy skipped")
            return
        }
        val altitude = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                location.hasMslAltitude() -> location.mslAltitudeMeters
            location.hasAltitude() -> location.altitude
            else -> null
        }
        log(
            "position from ${location.provider}: accuracy ${location.accuracy} m, " +
                "${System.currentTimeMillis() - location.time} ms old",
        )
        channel.invokeMethod(
            "fix",
            mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "altitude" to altitude,
                "accuracy" to location.accuracy.toDouble(),
                "timeMs" to location.time,
                "speed" to if (location.hasSpeed()) location.speed.toDouble() else null,
            ),
        )
    }

    private fun onProviderChanged(provider: String, state: String) {
        if (!running || disposed) return
        val answer = access()
        log("provider $provider $state; location access $answer")
        channel.invokeMethod("accessChanged", answer)
    }

    /** Puts the latest [notice] on the service's notification. */
    private fun showNotice() {
        val next = notice ?: return
        if (next == shownNotice) return
        shownNotice = next
        GeotagService.update(context, next)
    }

    private fun failStart(code: String, message: String) {
        if (startRequests.isEmpty()) return
        log("start ended: $code: $message")
        startRequests.forEach { it.error(code, message, null) }
        startRequests.clear()
    }

    /** Ends the run: no updates, no wake lock, no service. */
    private fun endRun() {
        // First, so the service's onDestroy is not taken for Android's doing.
        running = false
        removeUpdates()
        if (wakeLock.isHeld) wakeLock.release()
        shownNotice = null
        context.stopService(GeotagService.intent(context))
        log("run ended; updates removed, wake lock released, service stopped")
    }
}

/** Android's permission request code for [LocationChannel]; the app's own is 1. */
private const val PERMISSION_REQUEST = 0x4752

/** The request code of [LocationChannel]'s question about notifications. */
private const val NOTIFICATION_REQUEST = 0x4753

private const val TAG = "GrPhotoLocation"
