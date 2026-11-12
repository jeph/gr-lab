package io.jeph.grphoto.gr_camera

import android.content.Context
import android.util.Log
import java.time.Instant

/**
 * The log of one of the plugin's channels whose native code also runs with
 * no Flutter engine (a receiver woken for a position or after a restart
 * of the phone).
 *
 * As everywhere in the plugin, a line goes to logcat and to Dart (`log` on
 * the channel, which records it in the camera trace), and only while the
 * app's "Enable debug logging" is on. Two things differ from [WifiChannel],
 * because the lines that explain what happened with the app closed are
 * written with no Dart side to take them:
 *
 * - the setting is kept in the app's preferences, so a process started for
 *   a broadcast knows it;
 * - lines written while no Dart side listens are held, the newest
 *   [HELD_LINES] of them, and handed over when it turns logging on.
 *
 * Used on the main thread only.
 */
internal class NativeLog(private val tag: String, private val key: String) {
    private var enabled: Boolean? = null
    private var sink: ((String) -> Unit)? = null
    private val held = ArrayDeque<String>()

    /** Logs [message]; nothing while logging is off. */
    fun log(context: Context, message: String) {
        if (!isEnabled(context)) return
        Log.i(tag, message)
        val send = sink
        if (send != null) {
            send(message)
            return
        }
        if (held.size == HELD_LINES) held.removeFirst()
        held.addLast("$message (logged ${Instant.now()}, before the app listened)")
    }

    /**
     * The Dart side's `setLogging`: keeps the setting and, when on, sends
     * the held lines and every later one through [send].
     */
    fun setLogging(context: Context, on: Boolean, send: (String) -> Unit) {
        enabled = on
        preferences(context).edit().putBoolean(key, on).apply()
        if (!on) {
            sink = null
            held.clear()
            return
        }
        sink = send
        while (held.isNotEmpty()) send(held.removeFirst())
    }

    /** The Dart side is gone; later lines are held for the next one. */
    fun detach() {
        sink = null
    }

    private fun isEnabled(context: Context): Boolean {
        enabled?.let { return it }
        val kept = preferences(context).getBoolean(key, false)
        enabled = kept
        return kept
    }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences("gr_camera_log", Context.MODE_PRIVATE)
}

/** The log of the location code. */
internal object Logs {
    val location = NativeLog("GrPhotoLocation", "location")
}

private const val HELD_LINES = 200
