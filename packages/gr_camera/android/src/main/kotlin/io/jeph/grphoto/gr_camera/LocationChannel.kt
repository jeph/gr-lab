package io.jeph.grphoto.gr_camera

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.LocationRequest
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException

/**
 * `io.jeph.grphoto/location`: the phone's location for the camera layer.
 * Three uses, independent of each other:
 *
 * - Precise positions for a camera that is on: continuous ones
 *   (`startUpdates`, each sent as `fix`) and a single new one (`current`),
 *   from Android's own location service. They come from the fused provider
 *   where the phone has one, otherwise from GPS and the network provider
 *   together.
 * - The run that keeps the app going with its screen off while live
 *   geotagging runs or waits (`holdRun`, `releaseRun`): [GeotagService].
 *   Some makers' Android builds freeze an app with the screen off even
 *   while it holds a foreground service, until the user exempts it from
 *   battery optimisation: `backgroundUnrestricted` reads that exemption and
 *   `requestBackgroundUnrestricted` shows Android's question about it.
 * - The location history recorded with the app closed (`setHistory`,
 *   `takeHistory`): [HistoryRecorder] and [HistoryStore].
 *
 * The access the user allows is reported, never assumed: `access` reads
 * it, the two requests prompt for it, and `accessChanged` follows every
 * prompt, every return of the app to the screen and the phone's location
 * switch. Prompts need the app's activity, which [GrCameraPlugin] passes
 * in; with none (the app's task was swiped away while a run is held) a
 * request answers with the access as it is.
 *
 * Every callback runs on the main looper, the same thread as the method
 * channel, so the state needs no locking; only the history file is read
 * and written elsewhere ([HistoryStore.io]).
 *
 * Log lines follow [NativeLog]. Positions of the history never reach the
 * log, only how many there were.
 */
class LocationChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {
    private val channel = MethodChannel(messenger, "io.jeph.grphoto/location")
    private val main = Handler(Looper.getMainLooper())
    private val manager: LocationManager? = context.getSystemService(LocationManager::class.java)
    private var activity: Activity? = null

    /** The Dart side listens to positions; kept while access is missing. */
    private var updatesWanted = false

    /** [updates] is registered with Android. */
    private var updating = false
    private val updates = LocationListener { location ->
        GeotagService.alive()
        channel.invokeMethod("fix", location.toFix())
    }

    /** The `current` calls still waiting for a position. */
    private val currents = mutableSetOf<Current>()

    /** The calls waiting for the answer to each permission prompt. */
    private val prompts = mutableMapOf<Int, MutableList<MethodChannel.Result>>()

    /**
     * The calls waiting for the user to answer Android's question about
     * battery optimisation, which reports no result: they are answered
     * when the app is back on screen.
     */
    private val exemptionAsks = mutableListOf<MethodChannel.Result>()
    private var askedToNotify = false

    /** The activity is resumed; [GrCameraPlugin] reports changes. */
    private var resumed = false

    /** The phone's location switch changed. */
    private val modeReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            accessChanged()
        }
    }

    init {
        channel.setMethodCallHandler(this)
        attachedChannel = this
        GeotagService.onStopped = {
            log("the run was stopped from its notification")
            channel.invokeMethod("runStopped", null)
        }
        context.registerReceiver(
            modeReceiver,
            IntentFilter(LocationManager.MODE_CHANGED_ACTION),
            Context.RECEIVER_NOT_EXPORTED,
        )
        HistoryRecorder.sync(context)
    }

    /** The activity prompts are shown over, or null when the app has none. */
    fun onActivity(next: Activity?) {
        activity = next
        if (next != null) return
        resumed = false
        answerExemptionAsks()
        // A prompt cannot be answered any more.
        val waiting = prompts.values.flatten()
        prompts.clear()
        if (waiting.isEmpty()) return
        val access = LocationAccess.toMap(context)
        for (result in waiting) result.success(access)
    }

    /**
     * The app is on screen (again): the user may have been in the settings,
     * and a run held while it was not may still have to ask about
     * notifications.
     */
    fun onResume() {
        resumed = true
        answerExemptionAsks()
        accessChanged()
        GeotagService.refresh()
        askToNotify()
    }

    fun onPause() {
        resumed = false
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (attachedChannel === this) attachedChannel = null
        GeotagService.onStopped = null
        context.unregisterReceiver(modeReceiver)
        stopUpdates()
        for (current in currents.toList()) current.finish(null)
        onActivity(null)
        // The Dart side is gone, and the run it held with it.
        GeotagService.release()
        Logs.location.detach()
    }

    private fun log(message: String) = Logs.location.log(context, message)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "access" -> result.success(LocationAccess.toMap(context))
            "requestWhileInUse" -> requestWhileInUse(result)
            "requestAlways" -> requestAlways(result)
            "openSettings" -> openSettings(call, result)
            "startUpdates" -> {
                updatesWanted = true
                startUpdates()
                result.success(null)
            }
            "stopUpdates" -> {
                updatesWanted = false
                stopUpdates()
                result.success(null)
            }
            "current" -> current(call, result)
            "holdRun" -> holdRun(call, result)
            "releaseRun" -> {
                log("run released")
                GeotagService.release()
                result.success(null)
            }
            "backgroundUnrestricted" -> result.success(backgroundUnrestricted())
            "requestBackgroundUnrestricted" -> requestBackgroundUnrestricted(result)
            "setHistory" -> setHistory(call, result)
            // The notification goes when the app's process ends, so no Stop
            // is ever pressed on one that outlived its run.
            "takeRunStop" -> result.success(null)
            "takeHistory" -> takeHistory(result)
            "setLogging" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                Logs.location.setLogging(context, enabled) { channel.invokeMethod("log", it) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestWhileInUse(result: MethodChannel.Result) {
        val over = activity
        if (over == null || LocationAccess.precise(context)) {
            result.success(LocationAccess.toMap(context))
            return
        }
        // Both together: Android offers "Precise" and "Approximate" in one
        // prompt, and refuses a request for the precise permission alone.
        prompt(
            over,
            WHILE_IN_USE_REQUEST,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            result,
        )
    }

    private fun requestAlways(result: MethodChannel.Result) {
        val over = activity
        // Android ignores the request until location is allowed while the
        // app is in use.
        if (over == null || LocationAccess.always(context) || !LocationAccess.whileInUse(context)) {
            result.success(LocationAccess.toMap(context))
            return
        }
        // Android shows the app's location settings page for this one, and
        // answers when the user comes back.
        prompt(over, ALWAYS_REQUEST, arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), result)
    }

    /**
     * Asks for [permissions] over [over]; [result] gets the access once
     * Android answers ([onRequestPermissionsResult]), which is at once
     * when it no longer prompts.
     */
    private fun prompt(over: Activity, code: Int, permissions: Array<String>, result: MethodChannel.Result) {
        val waiting = prompts.getOrPut(code) { mutableListOf() }
        waiting += result
        // The prompt is up already; its answer is for this call too.
        if (waiting.size > 1) return
        log("asking for ${permissions.joinToString { it.substringAfterLast('.') }}")
        over.requestPermissions(permissions, code)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode == NOTIFICATION_REQUEST) return true
        // The granted state is read back rather than taken from the
        // answer, which is empty when Android dropped the request.
        val waiting = prompts.remove(requestCode) ?: return false
        val access = accessChanged()
        for (result in waiting) result.success(access)
        // The question about notifications waited for this one.
        askToNotify()
        return true
    }

    /**
     * Tells the Dart side the access as it is now, and brings what depends
     * on it in line: the history's request and positions the Dart side
     * waits for.
     */
    private fun accessChanged(): Map<String, Any> {
        val access = LocationAccess.toMap(context)
        log("access $access")
        HistoryRecorder.sync(context)
        if (updatesWanted) startUpdates()
        channel.invokeMethod("accessChanged", access)
        return access
    }

    private fun openSettings(call: MethodCall, result: MethodChannel.Result) {
        val page = when (call.argument<String>("page")) {
            "app" -> Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null),
            )
            "phone" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            else -> {
                result.error("failed", "openSettings needs page: app or phone", null)
                return
            }
        }
        try {
            val over = activity
            if (over != null) over.startActivity(page) else context.startActivity(page.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("failed", "the phone has no such settings page: ${e.message}", null)
        }
    }

    /** The providers precise positions come from; see the class comment. */
    private fun liveProviders(manager: LocationManager): List<String> {
        if (manager.hasProvider(LocationManager.FUSED_PROVIDER)) return listOf(LocationManager.FUSED_PROVIDER)
        return listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).filter(manager::hasProvider)
    }

    /**
     * Registers for positions when the Dart side wants them and access
     * allows; called again whenever the access may have changed.
     */
    private fun startUpdates() {
        if (updating) return
        val manager = manager ?: return
        if (!LocationAccess.whileInUse(context)) {
            log("no positions yet: location is not allowed")
            return
        }
        for (provider in liveProviders(manager)) {
            try {
                manager.requestLocationUpdates(provider, liveRequest, context.mainExecutor, updates)
                updating = true
                log("positions requested from the $provider provider")
            } catch (e: SecurityException) {
                log("Android refused positions from the $provider provider: ${e.message}")
            } catch (e: IllegalArgumentException) {
                log("Android refused positions from the $provider provider: ${e.message}")
            }
        }
        if (!updating) log("no positions: no provider gives any")
    }

    private fun stopUpdates() {
        if (!updating) return
        updating = false
        manager?.removeUpdates(updates)
        log("positions no longer requested")
    }

    private fun current(call: MethodCall, result: MethodChannel.Result) {
        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong()
        if (timeoutMs == null || timeoutMs <= 0) {
            result.error("failed", "current needs a positive timeoutMs", null)
            return
        }
        GeotagService.alive()
        val manager = manager
        val providers = if (manager != null && LocationAccess.whileInUse(context)) liveProviders(manager) else emptyList()
        if (manager == null || providers.isEmpty()) {
            log("no current position: location is not allowed or the phone has no provider")
            result.success(null)
            return
        }
        val request = LocationRequest.Builder(LIVE_INTERVAL_MS)
            .setQuality(LocationRequest.QUALITY_HIGH_ACCURACY)
            .setDurationMillis(timeoutMs)
            .build()
        val current = Current(result, providers.size)
        currents += current
        main.postDelayed(current.timeout, timeoutMs)
        for (provider in providers) {
            val signal = CancellationSignal()
            current.signals += signal
            try {
                manager.getCurrentLocation(provider, request, signal, context.mainExecutor) { location: Location? ->
                    current.answer(provider, location)
                }
            } catch (e: SecurityException) {
                current.answer(provider, null)
            } catch (e: IllegalArgumentException) {
                current.answer(provider, null)
            }
        }
    }

    /**
     * One `current` call: the first new position from any of its providers
     * answers it, or null when none gave one in time.
     *
     * Android's `getCurrentLocation` may hand back a position it already
     * had (up to some seconds old by its documentation, 30 s in AOSP). The
     * camera layer asks because it must not send a stored one, so anything
     * older than [NEW_FIX_MS] counts as none.
     */
    private inner class Current(private val result: MethodChannel.Result, private var open: Int) {
        val signals = mutableListOf<CancellationSignal>()
        val timeout = Runnable {
            log("no current position in time")
            finish(null)
        }
        private var done = false

        fun answer(provider: String, location: Location?) {
            if (done) return
            open--
            if (location == null) {
                log("the $provider provider gave no current position")
            } else {
                val ageMs = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
                if (ageMs <= NEW_FIX_MS) {
                    finish(location)
                    return
                }
                log("the $provider provider gave a position $ageMs ms old; not used")
            }
            if (open == 0) finish(null)
        }

        fun finish(location: Location?) {
            if (done) return
            done = true
            currents -= this
            main.removeCallbacks(timeout)
            for (signal in signals) signal.cancel()
            result.success(location?.toFix())
        }
    }

    /**
     * Android leaves the app out of battery optimisation. Without a power
     * service there is nothing the user could allow.
     */
    private fun backgroundUnrestricted(): Boolean =
        context.getSystemService(PowerManager::class.java)
            ?.isIgnoringBatteryOptimizations(context.packageName) ?: true

    /**
     * Shows Android's question whether the app may be left out of battery
     * optimisation; [result] gets the state once the app is back on screen.
     * With no activity to show it over, or nothing left to allow, it gets
     * the state as it is.
     */
    private fun requestBackgroundUnrestricted(result: MethodChannel.Result) {
        val over = activity
        if (over == null || backgroundUnrestricted()) {
            result.success(backgroundUnrestricted())
            return
        }
        exemptionAsks += result
        // The question is up already; its answer is for this call too.
        if (exemptionAsks.size > 1) return
        log("asking to be left out of battery optimisation")
        try {
            over.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.fromParts("package", context.packageName, null),
                ),
            )
        } catch (e: ActivityNotFoundException) {
            log("the phone has no question about battery optimisation: ${e.message}")
            answerExemptionAsks()
        }
    }

    private fun answerExemptionAsks() {
        if (exemptionAsks.isEmpty()) return
        val unrestricted = backgroundUnrestricted()
        log("left out of battery optimisation: $unrestricted")
        val waiting = exemptionAsks.toList()
        exemptionAsks.clear()
        for (result in waiting) result.success(unrestricted)
    }

    private fun holdRun(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title")
        val text = call.argument<String>("text")
        val stopLabel = call.argument<String>("stopLabel")
        val channelName = call.argument<String>("channel")
        val awake = call.argument<Boolean>("awake")
        if (title == null || text == null || stopLabel == null || channelName == null || awake == null) {
            result.error("failed", "holdRun needs title, text, stopLabel, channel and awake", null)
            return
        }
        if (!LocationAccess.whileInUse(context) || !LocationAccess.serviceOn(context)) {
            result.error("noAccess", "location is not allowed or is off for the phone", null)
            return
        }
        log("run held: \"$title\" / \"$text\", awake $awake")
        GeotagService.hold(context, GeotagService.Notice(title, text, stopLabel, channelName), awake) { failure ->
            if (failure == null) {
                result.success(null)
            } else {
                log("run not held: ${failure.code}: ${failure.message}")
                result.error(failure.code, failure.message, null)
            }
        }
        askToNotify()
    }

    /**
     * Asks for the notification permission (Android 13 and later), once
     * per launch, while a run is held. Android only shows the question
     * over an app that is on screen, and one question at a time, so it is
     * put when the run is held, or else as soon as both are true: when the
     * app is next resumed (a run held while the app was in the background)
     * or the prompt that was open is answered. Refused, the run still works and Android
     * lists it under its active apps, without the notification and its
     * Stop button.
     */
    private fun askToNotify() {
        if (askedToNotify || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (!GeotagService.held || !resumed || prompts.isNotEmpty()) return
        val over = activity ?: return
        askedToNotify = true
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (over.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return
        log("asking for POST_NOTIFICATIONS")
        over.requestPermissions(arrayOf(permission), NOTIFICATION_REQUEST)
    }

    private fun setHistory(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled")
        if (enabled == null) {
            result.error("failed", "setHistory needs enabled", null)
            return
        }
        log("history turned ${if (enabled) "on" else "off"}")
        HistoryRecorder.setEnabled(context, enabled)
        result.success(null)
    }

    private fun takeHistory(result: MethodChannel.Result) {
        HistoryStore.io.execute {
            val fixes = try {
                HistoryStore.take(context)
            } catch (e: IOException) {
                main.post { result.error("failed", "the recorded positions could not be read: ${e.message}", null) }
                return@execute
            }
            main.post {
                log("history: ${fixes.size} position(s) handed over")
                result.success(fixes)
            }
        }
    }

    internal companion object {
        /** The channel of the Flutter engine that is attached, if any. */
        private var attachedChannel: LocationChannel? = null

        /** [HistoryReceiver] recorded a position: tells an attached Dart side. */
        fun historyRecorded() {
            attachedChannel?.channel?.invokeMethod("historyPending", null)
        }
    }
}

private const val LIVE_INTERVAL_MS = 1000L

private val liveRequest: LocationRequest = LocationRequest.Builder(LIVE_INTERVAL_MS)
    .setQuality(LocationRequest.QUALITY_HIGH_ACCURACY)
    .build()

/** A position from `getCurrentLocation` older than this was a stored one. */
private const val NEW_FIX_MS = 10 * 1000L

// Request codes are shared with the activity and every other plugin.
private const val WHILE_IN_USE_REQUEST = 0x4701
private const val ALWAYS_REQUEST = 0x4702
private const val NOTIFICATION_REQUEST = 0x4703
