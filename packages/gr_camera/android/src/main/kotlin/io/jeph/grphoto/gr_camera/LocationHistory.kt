package io.jeph.grphoto.gr_camera

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.location.LocationRequest
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The positions recorded for the location history and not yet handed to
 * the Dart side: a file in the app's private storage that is kept out of
 * backups.
 *
 * One record is 40 bytes: the fix time (milliseconds since the epoch), then
 * latitude, longitude, accuracy and altitude as doubles, NaN for a value
 * the phone did not give. Records are appended as they arrive. Fixed-size
 * records make the common append cheap: the count is the file length and
 * the oldest record is the first, so the file is only rewritten when that
 * one is older than [KEEP_MS] or the file is full.
 *
 * [HistoryReceiver] appends from a process that may have been started for
 * it alone while the Dart side takes the records, so every access holds
 * the lock and runs on [io], off the main thread.
 */
internal object HistoryStore {
    /** Where the file is read and written. */
    val io: ExecutorService by lazy { Executors.newSingleThreadExecutor() }

    /**
     * Appends [location], dropping records older than [KEEP_MS] and all but
     * the newest [MAX_RECORDS]. False when the fix itself is too old to keep.
     */
    @Synchronized
    @Throws(IOException::class)
    fun append(context: Context, location: Location): Boolean {
        val oldestKept = System.currentTimeMillis() - KEEP_MS
        if (location.time < oldestKept) return false
        RandomAccessFile(file(context), "rw").use { store ->
            // A process that died while writing leaves part of a record.
            val whole = store.length() / RECORD_BYTES * RECORD_BYTES
            if (whole != store.length()) store.setLength(whole)
            if (whole > 0) {
                val full = whole / RECORD_BYTES >= MAX_RECORDS
                if (full || store.readLong() < oldestKept) prune(store, oldestKept)
            }
            store.seek(store.length())
            store.write(record(location))
        }
        return true
    }

    /** The recorded fixes as fix maps, oldest first; the store is emptied. */
    @Synchronized
    @Throws(IOException::class)
    fun take(context: Context): List<Map<String, Any>> {
        val file = file(context)
        if (!file.exists()) return emptyList()
        val records = ByteBuffer.wrap(file.readBytes())
        val fixes = ArrayList<Map<String, Any>>(records.remaining() / RECORD_BYTES)
        while (records.remaining() >= RECORD_BYTES) {
            val time = records.getLong()
            val latitude = records.getDouble()
            val longitude = records.getDouble()
            val accuracy = records.getDouble()
            val altitude = records.getDouble()
            fixes += buildMap<String, Any> {
                put("lat", latitude)
                put("lon", longitude)
                put("t", time)
                if (!accuracy.isNaN()) put("acc", accuracy)
                if (!altitude.isNaN()) put("alt", altitude)
            }
        }
        if (!file.delete()) throw IOException("the recorded positions could not be removed")
        // Appended as they arrived, which is by time except when the
        // phone's clock was set back.
        fixes.sortBy { it["t"] as Long }
        return fixes
    }

    /**
     * Rewrites [store] without the records older than [oldestKept], and
     * with room for one more under [MAX_RECORDS].
     */
    private fun prune(store: RandomAccessFile, oldestKept: Long) {
        val all = ByteArray(store.length().toInt())
        store.seek(0)
        store.readFully(all)
        val records = ByteBuffer.wrap(all)
        val kept = ByteBuffer.allocate(all.size)
        for (offset in all.indices step RECORD_BYTES) {
            if (records.getLong(offset) < oldestKept) continue
            kept.put(all, offset, RECORD_BYTES)
        }
        val excess = kept.position() - (MAX_RECORDS - 1) * RECORD_BYTES
        val from = if (excess > 0) excess else 0
        store.seek(0)
        store.write(kept.array(), from, kept.position() - from)
        store.setLength((kept.position() - from).toLong())
    }

    private fun record(location: Location): ByteArray = ByteBuffer.allocate(RECORD_BYTES)
        .putLong(location.time)
        .putDouble(location.latitude)
        .putDouble(location.longitude)
        .putDouble(if (location.hasAccuracy()) location.accuracy.toDouble() else Double.NaN)
        .putDouble(if (location.hasAltitude()) location.altitude else Double.NaN)
        .array()

    private fun file(context: Context) = File(context.noBackupFilesDir, "location-history.bin")
}

/**
 * Records where the phone is for the location history, with the app closed
 * too: a standing request to Android's location service that delivers to
 * [HistoryReceiver].
 *
 * The request asks for a position every five minutes at balanced power.
 * With the app not in front Android answers it only a few times an hour
 * (developer.android.com, "Background Location Limits"), which is the
 * sparse history that was chosen: no foreground service, no notification.
 * It comes from the fused provider where the phone has one, otherwise from
 * the network provider, otherwise from positions other apps asked for
 * (passive); never from GPS alone, which would run the receiver all day.
 *
 * The request exists only while the history is turned on ([setEnabled],
 * kept in the app's preferences) and location is allowed all the time.
 * Android drops it when the phone restarts and may when the app is
 * updated, so [sync] runs again then ([BootReceiver]), whenever the plugin
 * attaches to an engine and whenever the access may have changed.
 */
internal object HistoryRecorder {
    private const val PREFERENCES = "gr_camera_location"
    private const val ENABLED = "history"

    private val request = LocationRequest.Builder(5 * 60 * 1000L)
        .setMinUpdateIntervalMillis(60 * 1000L)
        .setQuality(LocationRequest.QUALITY_BALANCED_POWER_ACCURACY)
        .build()

    /** What [sync] did last in this process, so the log only has changes. */
    private var state: String? = null

    /** The user turned the history on. */
    fun enabled(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(ENABLED, false)

    /** Turns the history on or off, for this and every later start. */
    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putBoolean(ENABLED, enabled).apply()
        sync(context)
    }

    /** Files the request, or withdraws it when the history may not record. */
    fun sync(context: Context) {
        val manager = context.getSystemService(LocationManager::class.java) ?: return
        val deliver = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, HistoryReceiver::class.java).setAction(HistoryReceiver.ACTION_POSITION),
            // Mutable: Android adds the position to the intent.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val next = when {
            !enabled(context) -> "off"
            !LocationAccess.always(context) -> "waiting for location to be allowed all the time"
            else -> record(manager, deliver)
        }
        if (!next.startsWith(RECORDING)) manager.removeUpdates(deliver)
        if (next == state) return
        state = next
        Logs.location.log(context, "history: $next")
    }

    /** Files the request with the cheapest provider; what happened, for the log. */
    private fun record(manager: LocationManager, deliver: PendingIntent): String {
        val provider = listOf(
            LocationManager.FUSED_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        ).firstOrNull(manager::hasProvider) ?: return "the phone has no location provider to record from"
        return try {
            // Filing it again with the same PendingIntent replaces the request.
            manager.requestLocationUpdates(provider, request, deliver)
            "$RECORDING through the $provider provider"
        } catch (e: SecurityException) {
            "Android refused the request: ${e.message}"
        } catch (e: IllegalArgumentException) {
            "Android refused the request: ${e.message}"
        }
    }

    private const val RECORDING = "recording"
}

/**
 * Receives the positions [HistoryRecorder] asked for and appends them to
 * [HistoryStore]. Android starts the app's process for it when needed; no
 * Flutter engine is involved, and one that runs is only told that there is
 * something to take (`historyPending`).
 *
 * The positions never reach the log: only that one was recorded.
 */
class HistoryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_POSITION) return
        val app = context.applicationContext
        if (!HistoryRecorder.enabled(app) || !LocationAccess.always(app)) {
            // Turned off or no longer allowed since the request was filed.
            HistoryRecorder.sync(app)
            return
        }
        // Android also reports the provider being switched on and off here.
        val location = intent.parcelable(LocationManager.KEY_LOCATION_CHANGED, Location::class.java) ?: return
        val pending = goAsync()
        HistoryStore.io.execute {
            val outcome = try {
                if (HistoryStore.append(app, location)) null else "a position too old to keep was left out"
            } catch (e: IOException) {
                "a position could not be stored: ${e.message}"
            }
            Handler(Looper.getMainLooper()).post {
                if (outcome == null) {
                    Logs.location.log(app, "history: one position recorded")
                    LocationChannel.historyRecorded()
                } else {
                    Logs.location.log(app, "history: $outcome")
                }
                pending.finish()
            }
        }
    }

    internal companion object {
        const val ACTION_POSITION = "io.jeph.grphoto.gr_camera.HISTORY_POSITION"
    }
}

/** Ninety days: how long a recorded position is kept. */
private const val KEEP_MS = 90L * 24 * 60 * 60 * 1000

/** The most positions the store holds; the oldest go first. */
private const val MAX_RECORDS = 20_000

private const val RECORD_BYTES = 40
