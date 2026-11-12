package io.jeph.grphoto.gr_camera

import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock

/**
 * Receives what [PowerOnScan] finds: a watched camera advertising in its
 * on state, or (where the Bluetooth chip tracks it) no longer doing so.
 * Android starts the app's process for it when needed.
 *
 * A camera seen on is passed to the Dart side (`seenOn`) when a Flutter
 * engine is attached and listening; the Dart side decides what to do.
 * Otherwise the sighting is kept for it (`takeLaunchSightings`) and, when
 * no engine exists at all, live geotagging is started without the app:
 * [GeotagService] is started, which starts the engine. That needs location
 * allowed all the time (Android gives a service started from the
 * background no location otherwise) and a companion device association
 * with the camera (Android lets no other app start a foreground service
 * from the background), so without either the sighting is only kept.
 *
 * A sighting is the camera's first advertisement since it was last away.
 * With a first-match scan Android reports just that; with a scan that
 * reports every advertisement, it is one that follows [DEBOUNCE_MS]
 * without any.
 *
 * After the user stopped the run from its notification, a camera that is
 * still on must not start it again. So a start is held back
 * ([WatchStore.stopped]) until the camera has been off: until Android
 * reports the match lost, or, with a scan that cannot report that, until
 * no watched camera advertised on for [GONE_MS]. The Dart side arming the
 * watch again ends it too, as it does when it sees the camera go off.
 *
 * Runs on the main thread, as every receiver does.
 */
class WatchReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_SCAN) return
        val app = context.applicationContext
        val error = intent.getIntExtra(BluetoothLeScanner.EXTRA_ERROR_CODE, 0)
        if (error != 0) {
            log(app, "the scan failed with error $error")
            return
        }
        val type = intent.getIntExtra(
            BluetoothLeScanner.EXTRA_CALLBACK_TYPE,
            ScanSettings.CALLBACK_TYPE_ALL_MATCHES,
        )
        val watched = WatchStore.cameras(app)
        for (result in intent.parcelableList(BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT, ScanResult::class.java)) {
            val deviceId = result.device.address
            when {
                // Left from a scan for an earlier list.
                deviceId !in watched -> Unit
                type == ScanSettings.CALLBACK_TYPE_MATCH_LOST -> lost(app, deviceId)
                // Its manufacturer data says otherwise: not a sighting.
                saysOff(result) -> log(app, "$deviceId matched with power off in its manufacturer data; ignored")
                else -> advertisedOn(app, deviceId, type)
            }
        }
    }

    private fun lost(context: Context, deviceId: String) {
        log(context, "$deviceId no longer advertises on")
        if (!WatchStore.stopped(context)) return
        WatchStore.setStopped(context, false)
        log(context, "the camera went off after the run was stopped; its next power-on starts it again")
    }

    private fun advertisedOn(context: Context, deviceId: String, type: Int) {
        val first = type == ScanSettings.CALLBACK_TYPE_FIRST_MATCH || firstSince(deviceId)
        // Asked on every advertisement: it notes when one was last seen.
        val stopped = WatchStore.stopped(context) && !stopIsOver(context, type)
        if (!first) return
        if (WatchChannel.seenOn(deviceId)) {
            log(context, "$deviceId is on; told the app")
            return
        }
        WatchStore.addLaunchSighting(context, deviceId)
        when {
            WatchChannel.attached ->
                log(context, "$deviceId is on; kept for the app, which is starting")
            stopped ->
                log(context, "$deviceId is on; not starting, the run was stopped from its notification")
            !LocationAccess.always(context) ->
                log(context, "$deviceId is on; not starting, location is not allowed all the time")
            !CameraAssociation.exists(context, deviceId) ->
                log(context, "$deviceId is on; not starting, the camera is not an associated companion device")
            else -> {
                val failure = GeotagService.launch(context)
                if (failure == null) {
                    log(context, "$deviceId is on; starting live geotagging without the app")
                } else {
                    log(context, "$deviceId is on; live geotagging did not start: $failure")
                }
            }
        }
    }

    /**
     * Whether the camera has been off since the run was stopped, for a
     * scan that reports every advertisement and never a lost match.
     */
    private fun stopIsOver(context: Context, type: Int): Boolean {
        if (type == ScanSettings.CALLBACK_TYPE_FIRST_MATCH) return false
        val unseenMs = WatchStore.stoppedSeenAgain(context)
        if (unseenMs < GONE_MS) return false
        WatchStore.setStopped(context, false)
        log(context, "no camera advertised on for $unseenMs ms after the run was stopped; starting is allowed again")
        return true
    }

    /**
     * Whether this advertisement of [deviceId] is its first for
     * [DEBOUNCE_MS], in a scan that reports every one. What was seen under
     * an earlier scan, or by a process that has ended, does not count.
     */
    private fun firstSince(deviceId: String): Boolean {
        if (seenUnder != PowerOnScan.generation) {
            seenUnder = PowerOnScan.generation
            lastSeen.clear()
        }
        val now = SystemClock.elapsedRealtime()
        val last = lastSeen.put(deviceId, now)
        return last == null || now - last >= DEBOUNCE_MS
    }

    /**
     * The Ricoh manufacturer data, when the result has it, says the camera
     * is off: `DA 01 <model> 02 <serial u32 LE> 03 <power>` with power
     * `00` (`research/camera-models.md` §4.1). It is in the scan response,
     * which a result need not carry.
     */
    private fun saysOff(result: ScanResult): Boolean {
        val data = result.scanRecord?.getManufacturerSpecificData(RICOH_COMPANY_ID) ?: return false
        return data.size >= 10 &&
            data[0] == 0xDA.toByte() &&
            data[1] == 0x01.toByte() &&
            data[3] == 0x02.toByte() &&
            data[8] == 0x03.toByte() &&
            data[9] == 0x00.toByte()
    }

    private fun log(context: Context, message: String) = Logs.watch.log(context, "sighting: $message")

    internal companion object {
        const val ACTION_SCAN = "io.jeph.grphoto.gr_camera.WATCH_SCAN"

        /** When each camera last advertised on, by [SystemClock.elapsedRealtime]. */
        private val lastSeen = mutableMapOf<String, Long>()

        /** The [PowerOnScan.generation] that [lastSeen] belongs to. */
        private var seenUnder = 0
    }
}

/** Bluetooth SIG company ID of Ricoh Company Ltd. */
private const val RICOH_COMPANY_ID = 0x065F

/**
 * A camera that is on and not seen for this long was away: longer than a
 * low-power scan takes to hear a camera that advertises.
 */
private const val DEBOUNCE_MS = 30 * 1000L

/**
 * No camera seen on for this long after Stop means the camera was off.
 * Longer than [DEBOUNCE_MS]: taking a camera that is on for one that came
 * on would start the run the user just stopped.
 */
private const val GONE_MS = 2 * 60 * 1000L
