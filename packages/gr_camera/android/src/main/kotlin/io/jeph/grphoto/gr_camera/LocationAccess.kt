package io.jeph.grphoto.gr_camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager

/**
 * How far the user lets the app locate the phone, read from the granted
 * permissions and the phone's location switch. Never prompts.
 */
internal object LocationAccess {
    /** Precise positions are allowed. */
    fun precise(context: Context) = granted(context, Manifest.permission.ACCESS_FINE_LOCATION)

    /** Positions are allowed at least while the app is in use. */
    fun whileInUse(context: Context) =
        precise(context) || granted(context, Manifest.permission.ACCESS_COARSE_LOCATION)

    /** "Allow all the time": positions with the app not on screen too. */
    fun always(context: Context) =
        whileInUse(context) && granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)

    /** Location is switched on for the whole phone. */
    fun serviceOn(context: Context) =
        context.getSystemService(LocationManager::class.java)?.isLocationEnabled == true

    /** The access map of the location channel. */
    fun toMap(context: Context): Map<String, Any> = mapOf(
        "permission" to when {
            always(context) -> "always"
            whileInUse(context) -> "whileInUse"
            else -> "denied"
        },
        "precise" to precise(context),
        "service" to serviceOn(context),
    )

    private fun granted(context: Context, permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
}

/** The fix map of the location channel: `lat`, `lon`, `t`, and `acc` and `alt` when known. */
internal fun Location.toFix(): Map<String, Any> = buildMap<String, Any> {
    put("lat", latitude)
    put("lon", longitude)
    put("t", time)
    if (hasAccuracy()) put("acc", accuracy.toDouble())
    if (hasAltitude()) put("alt", altitude)
}
