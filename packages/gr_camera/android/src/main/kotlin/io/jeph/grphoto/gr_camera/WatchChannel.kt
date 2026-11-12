package io.jeph.grphoto.gr_camera

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanFilter
import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.BluetoothLeDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.IntentSender
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * `io.jeph.grphoto/watch`: noticing a paired camera being switched on
 * while the app is not on screen, or not running.
 *
 * `watch` names the cameras; [PowerOnScan] has Android's Bluetooth stack
 * look for them and [WatchReceiver] hears of it, with or without this
 * channel. A camera seen on reaches the Dart side as `seenOn` once it has
 * made its first call here (before that nothing listens, and the sighting
 * waits in `takeLaunchSightings`).
 *
 * `associate` asks the user to make the camera a companion device of the
 * app, in Android's own dialog. Android looks for the camera itself before
 * it shows the camera there, so the camera has to be in reach and
 * advertising (on, or off with its Bluetooth on). The association is what
 * lets [GeotagService] start from the background; nothing else is done
 * with it.
 *
 * The scan dies when Bluetooth is switched off. Android does not start a
 * manifest receiver for `BluetoothAdapter.ACTION_STATE_CHANGED` (it is not
 * among the exceptions on developer.android.com, "Implicit broadcast
 * exceptions"), so the scan is filed again from a receiver registered for
 * as long as an engine is attached; with none it is filed again the next
 * time one attaches, or the phone restarts.
 *
 * Every callback runs on the main looper, the same thread as the method
 * channel. Log lines follow [NativeLog].
 */
class WatchChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private val channel = MethodChannel(messenger, "io.jeph.grphoto/watch")
    private val main = Handler(Looper.getMainLooper())
    private var activity: Activity? = null

    /** The Dart side has called: its handler for `seenOn` is in place. */
    private var listening = false

    /** The `associate` call waiting for Android and the user. */
    private var associating: MethodChannel.Result? = null

    /** Ends an `associate` call Android never answers. */
    private val associationTimeout = Runnable {
        log("Android did not answer the association request")
        finishAssociation(false)
    }

    private val association = object : CompanionDeviceManager.Callback() {
        override fun onAssociationPending(intentSender: IntentSender) = showAssociation(intentSender)

        // Android 12 calls this one; Android 13 renamed it and calls
        // onAssociationPending instead.
        @Suppress("OVERRIDE_DEPRECATION")
        override fun onDeviceFound(intentSender: IntentSender) = showAssociation(intentSender)

        override fun onAssociationCreated(associationInfo: AssociationInfo) {
            log("associated")
            finishAssociation(true)
        }

        override fun onFailure(error: CharSequence?) {
            log("not associated: $error")
            finishAssociation(false)
        }
    }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
            if (state != BluetoothAdapter.STATE_ON) return
            log("Bluetooth is on again")
            PowerOnScan.restart(context)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        attachedChannel = this
        context.registerReceiver(
            bluetoothReceiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            Context.RECEIVER_NOT_EXPORTED,
        )
        PowerOnScan.restart(context)
    }

    /** The activity Android's association dialog is shown over, or null. */
    fun onActivity(next: Activity?) {
        activity = next
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (attachedChannel === this) attachedChannel = null
        context.unregisterReceiver(bluetoothReceiver)
        finishAssociation(false)
        Logs.watch.detach()
    }

    private fun log(message: String) = Logs.watch.log(context, message)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        listening = true
        when (call.method) {
            "supported" -> result.success(CameraAssociation.supported(context))
            "associated" -> {
                val deviceId = call.argument<String>("deviceId")
                if (deviceId == null) {
                    result.error("failed", "associated needs deviceId", null)
                } else {
                    result.success(CameraAssociation.exists(context, deviceId))
                }
            }
            "associate" -> associate(call, result)
            "watch" -> watch(call, result)
            "takeLaunchSightings" -> {
                val sightings = WatchStore.takeLaunchSightings(context)
                log("launch sightings taken: $sightings")
                result.success(sightings)
            }
            "setLogging" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                Logs.watch.setLogging(context, enabled) { channel.invokeMethod("log", it) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun associate(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId")
        val name = call.argument<String>("name")
        if (deviceId == null || name == null) {
            result.error("failed", "associate needs deviceId and name", null)
            return
        }
        if (CameraAssociation.exists(context, deviceId)) {
            result.success(true)
            return
        }
        val manager = CameraAssociation.manager(context)
        if (manager == null || activity == null) {
            log("\"$name\" ($deviceId) cannot be associated: " + if (manager == null) "not supported" else "no screen")
            result.success(false)
            return
        }
        // One dialog at a time: the earlier call is answered by the new one's outcome.
        finishAssociation(false)
        associating = result
        log("asking Android to associate \"$name\" ($deviceId)")
        try {
            val camera = BluetoothLeDeviceFilter.Builder()
                .setScanFilter(ScanFilter.Builder().setDeviceAddress(deviceId.uppercase()).build())
                .build()
            val request = AssociationRequest.Builder().addDeviceFilter(camera).setSingleDevice(true).build()
            manager.associate(request, association, main)
            main.postDelayed(associationTimeout, ASSOCIATION_ANSWER_MS)
        } catch (e: RuntimeException) {
            // Not a Bluetooth address, or Android refused the request.
            log("Android refused the association request: ${e.message}")
            finishAssociation(false)
        }
    }

    /** Android found the camera: shows its dialog over the activity. */
    private fun showAssociation(dialog: IntentSender) {
        // From here the user decides, in their own time.
        main.removeCallbacks(associationTimeout)
        val over = activity
        if (associating == null || over == null) {
            finishAssociation(false)
            return
        }
        try {
            over.startIntentSenderForResult(dialog, ASSOCIATION_REQUEST, null, 0, 0, 0)
        } catch (e: IntentSender.SendIntentException) {
            log("Android's association dialog did not open: ${e.message}")
            finishAssociation(false)
        }
    }

    /**
     * The association dialog closed. Android 13 and later also report the
     * outcome to [association]; whichever comes first answers the call.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != ASSOCIATION_REQUEST) return false
        if (resultCode != Activity.RESULT_OK) log("the association dialog was closed without associating")
        finishAssociation(resultCode == Activity.RESULT_OK)
        return true
    }

    private fun finishAssociation(associated: Boolean) {
        main.removeCallbacks(associationTimeout)
        val result = associating ?: return
        associating = null
        result.success(associated)
    }

    private fun watch(call: MethodCall, result: MethodChannel.Result) {
        val cameras = call.argument<List<Map<String, Any?>>>("cameras")
        val deviceIds = cameras?.map { it["deviceId"] as? String }
        if (deviceIds == null || deviceIds.any { it == null }) {
            result.error("failed", "watch needs cameras, each with deviceId and name", null)
            return
        }
        // Android's scan filter takes addresses in capitals only.
        WatchStore.setCameras(context, deviceIds.filterNotNull().map(String::uppercase).toSet())
        // Arming the watch starts afresh: the Dart side does it when it
        // saw the camera go off, which is what a stop waits for.
        WatchStore.setStopped(context, false)
        PowerOnScan.restart(context)
        result.success(null)
    }

    internal companion object {
        /** The channel of the Flutter engine that is attached, if any. */
        private var attachedChannel: WatchChannel? = null

        /** A Flutter engine is attached to the plugin. */
        val attached: Boolean
            get() = attachedChannel != null

        /**
         * Tells the Dart side that the camera [deviceId] advertises on;
         * false when none is listening.
         */
        fun seenOn(deviceId: String): Boolean {
            val to = attachedChannel ?: return false
            if (!to.listening) return false
            to.channel.invokeMethod("seenOn", mapOf("deviceId" to deviceId))
            return true
        }
    }
}

/** How long Android may take to find the camera before its dialog shows. */
private const val ASSOCIATION_ANSWER_MS = 30 * 1000L

// Request codes are shared with the activity and every other plugin.
private const val ASSOCIATION_REQUEST = 0x4711
