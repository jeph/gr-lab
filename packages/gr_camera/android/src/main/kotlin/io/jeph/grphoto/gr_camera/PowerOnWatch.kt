package io.jeph.grphoto.gr_camera

import android.Manifest
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.companion.CompanionDeviceManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid

/**
 * What the power-on watch keeps in the app's preferences, so it works in a
 * process Android started for a broadcast: the watched cameras, the
 * sightings that are waiting for the Dart side, and whether the user
 * stopped the run from its notification.
 */
internal object WatchStore {
    private const val CAMERAS = "cameras"
    private const val LAUNCH_SIGHTINGS = "launchSightings"
    private const val STOPPED = "stopped"
    private const val STOPPED_SEEN_AT = "stoppedSeenAt"

    /** The Bluetooth addresses of the watched cameras, in capitals. */
    fun cameras(context: Context): Set<String> =
        preferences(context).getStringSet(CAMERAS, null).orEmpty()

    /** Replaces the watched cameras. */
    fun setCameras(context: Context, deviceIds: Set<String>) {
        preferences(context).edit().putStringSet(CAMERAS, deviceIds).apply()
    }

    /** Keeps the sighting of [deviceId] for the Dart side to take when it runs. */
    fun addLaunchSighting(context: Context, deviceId: String) {
        val kept = preferences(context).getStringSet(LAUNCH_SIGHTINGS, null).orEmpty()
        if (deviceId in kept) return
        preferences(context).edit().putStringSet(LAUNCH_SIGHTINGS, kept + deviceId).apply()
    }

    /** The kept sightings; they are forgotten. */
    fun takeLaunchSightings(context: Context): List<String> {
        val kept = preferences(context).getStringSet(LAUNCH_SIGHTINGS, null).orEmpty()
        if (kept.isNotEmpty()) preferences(context).edit().remove(LAUNCH_SIGHTINGS).apply()
        return kept.sorted()
    }

    /**
     * The user stopped the run from its notification and no watched camera
     * has been seen off since: a camera that is still on must not start the
     * run again.
     */
    fun stopped(context: Context) = preferences(context).getBoolean(STOPPED, false)

    /** Sets or clears [stopped]. */
    fun setStopped(context: Context, stopped: Boolean) {
        val edit = preferences(context).edit()
        if (stopped) {
            edit.putBoolean(STOPPED, true).putLong(STOPPED_SEEN_AT, System.currentTimeMillis())
        } else {
            edit.remove(STOPPED).remove(STOPPED_SEEN_AT)
        }
        edit.apply()
    }

    /**
     * Notes that a watched camera advertises on now, while [stopped], and
     * returns how many milliseconds ago one last did (or the run was
     * stopped).
     */
    fun stoppedSeenAgain(context: Context): Long {
        val now = System.currentTimeMillis()
        val last = preferences(context).getLong(STOPPED_SEEN_AT, now)
        preferences(context).edit().putLong(STOPPED_SEEN_AT, now).apply()
        return now - last
    }

    private fun preferences(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences("gr_camera_watch", Context.MODE_PRIVATE)
}

/**
 * The Bluetooth scan that notices a watched camera being switched on, with
 * the app closed too: a scan filed with a `PendingIntent`, which Android's
 * Bluetooth stack keeps running after the app's process is gone and
 * answers by starting [WatchReceiver].
 *
 * A camera that is on advertises the Camera Information service; one that
 * is off advertises Client Registration instead (found in firmware and
 * observed on a GR IV HDF, `research/camera-models.md` §4.1,
 * `research/hardware-validation.md` §4). So there is one filter per
 * camera, on that service and the camera's address, which is its public
 * address (`research/protocol/firmware-bonding.md` §1). A filtered scan is
 * also the only kind Android keeps running with the screen off.
 *
 * Where the Bluetooth chip filters by itself
 * ([android.bluetooth.BluetoothAdapter.isOffloadedFilteringSupported]),
 * Android reports only a camera's first advertisement and its going away;
 * elsewhere it reports every advertisement and [WatchReceiver] tells the
 * first from the rest. The scan uses the low-power mode: it runs all day.
 *
 * Android forgets the scan when the phone restarts and when Bluetooth is
 * switched off, so it is filed again after a restart and an update of the
 * app ([BootReceiver]), when the plugin attaches to an engine, and when
 * Bluetooth comes back on while one is attached ([WatchChannel]).
 */
internal object PowerOnScan {
    /** The Camera Information service, advertised by a camera that is on. */
    private val cameraInformation =
        ParcelUuid.fromString("9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1")

    /**
     * Counts [restart]s in this process, so [WatchReceiver] forgets what
     * it saw under an earlier scan.
     */
    var generation = 0
        private set

    /**
     * Files the scan for the watched cameras afresh, so a camera that is
     * on is reported again; with no cameras the scan only stops.
     */
    fun restart(context: Context) {
        val app = context.applicationContext
        generation++
        val cameras = WatchStore.cameras(app)
        // Android throws without it. The app asks for it before it scans
        // for cameras, so it is only missing once the user took it away.
        if (app.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
            log(app, "the Nearby devices permission is missing; not watching ${cameras.size} camera(s)")
            return
        }
        val adapter = app.getSystemService(BluetoothManager::class.java)?.adapter
        val scanner = adapter?.bluetoothLeScanner
        if (adapter == null || scanner == null) {
            log(app, "Bluetooth is off; ${cameras.size} camera(s) are watched once it is on")
            return
        }
        val deliver = PendingIntent.getBroadcast(
            app,
            0,
            Intent(app, WatchReceiver::class.java).setAction(WatchReceiver.ACTION_SCAN),
            // Mutable: Android adds the scan results to the intent.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        try {
            scanner.stopScan(deliver)
        } catch (e: RuntimeException) {
            // Bluetooth went off in between; the scan is gone with it.
            log(app, "the earlier scan could not be stopped: ${e.message}")
        }
        if (cameras.isEmpty()) {
            log(app, "no cameras to watch; the scan is stopped")
            return
        }
        val filters = cameras.mapNotNull { filter(app, it) }
        if (filters.isEmpty()) return

        var mode = "first match and match lost"
        var error = if (adapter.isOffloadedFilteringSupported) {
            start(scanner, filters, settings(firstMatch = true), deliver)
        } else {
            "the Bluetooth chip does not filter by itself"
        }
        if (error != null) {
            // Also when the chip has no filter left to track the cameras.
            log(app, "no first-match scan ($error); scanning for every advertisement")
            mode = "every advertisement"
            error = start(scanner, filters, settings(firstMatch = false), deliver)
        }
        if (error == null) {
            log(app, "watching ${cameras.joinToString()} ($mode)")
        } else {
            log(app, "the scan for ${cameras.joinToString()} did not start: $error")
        }
    }

    private fun filter(context: Context, deviceId: String): ScanFilter? = try {
        ScanFilter.Builder().setServiceUuid(cameraInformation).setDeviceAddress(deviceId).build()
    } catch (e: IllegalArgumentException) {
        log(context, "\"$deviceId\" is not a Bluetooth address; not watched")
        null
    }

    private fun settings(firstMatch: Boolean): ScanSettings {
        val builder = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
        if (!firstMatch) return builder.setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES).build()
        return builder
            .setCallbackType(ScanSettings.CALLBACK_TYPE_FIRST_MATCH or ScanSettings.CALLBACK_TYPE_MATCH_LOST)
            // One filter matches one camera, so one advertisement is all
            // the chip has to track for it.
            .setNumOfMatches(ScanSettings.MATCH_NUM_ONE_ADVERTISEMENT)
            .build()
    }

    /** Null when the scan was filed, otherwise why not. */
    private fun start(
        scanner: BluetoothLeScanner,
        filters: List<ScanFilter>,
        settings: ScanSettings,
        deliver: PendingIntent,
    ): String? = try {
        val code = scanner.startScan(filters, settings, deliver)
        if (code == 0) null else "error $code"
    } catch (e: RuntimeException) {
        // Bluetooth went off in between (IllegalStateException), or the
        // permission did (SecurityException).
        "${e.javaClass.simpleName}: ${e.message}"
    }

    private fun log(context: Context, message: String) = Logs.watch.log(context, "scan: $message")
}

/**
 * Android's own link between the app and a camera: a companion device
 * association. An app that has one may start a foreground service from the
 * background (with `REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND`),
 * which is how [GeotagService] starts when a camera comes on with the app
 * closed.
 */
internal object CameraAssociation {
    /** The phone has Bluetooth LE and companion device associations. */
    fun supported(context: Context): Boolean {
        val features = context.packageManager
        return features.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) &&
            features.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)
    }

    /** Android's association service; null on a phone without it. */
    fun manager(context: Context): CompanionDeviceManager? {
        if (!supported(context)) return null
        return context.getSystemService(CompanionDeviceManager::class.java)
    }

    /** The app is associated with the camera at the address [deviceId]. */
    fun exists(context: Context, deviceId: String): Boolean {
        val manager = manager(context) ?: return false
        return try {
            addresses(manager).any { it.equals(deviceId, ignoreCase = true) }
        } catch (e: RuntimeException) {
            Logs.watch.log(context, "association: Android did not list the associations: ${e.message}")
            false
        }
    }

    private fun addresses(manager: CompanionDeviceManager): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return addressesBefore13(manager)
        return manager.myAssociations.mapNotNull { it.deviceMacAddress?.toString() }
    }

    // Deprecated since Android 13, where getMyAssociations came; this is
    // the only list Android 12 has.
    @Suppress("DEPRECATION")
    private fun addressesBefore13(manager: CompanionDeviceManager): List<String> = manager.associations
}
