package io.jeph.grphoto.gr_camera

import android.content.Intent
import android.os.Build
import android.os.Parcelable

/**
 * The parcelable extra [name] of the type [type].
 *
 * The typed getter exists from Android 13 but can throw there for a value
 * the system wrote (AndroidX `IntentCompat` uses it from Android 14 for
 * that reason), so earlier versions use the untyped one.
 */
internal fun <T : Parcelable> Intent.parcelable(name: String, type: Class<T>): T? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        return getParcelableExtra(name, type)
    }
    return untypedParcelable(name)
}

/** The list of parcelables in the extra [name]; see [parcelable]. */
internal fun <T : Parcelable> Intent.parcelableList(name: String, type: Class<T>): List<T> {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        return getParcelableArrayListExtra(name, type).orEmpty()
    }
    return untypedParcelableList<T>(name).orEmpty()
}

// Deprecated since Android 13, where the typed getters came; these are the
// only ones Android 12 has.
@Suppress("DEPRECATION")
private fun <T : Parcelable> Intent.untypedParcelable(name: String): T? = getParcelableExtra(name)

@Suppress("DEPRECATION")
private fun <T : Parcelable> Intent.untypedParcelableList(name: String): ArrayList<T>? =
    getParcelableArrayListExtra(name)
