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

// Deprecated since Android 13, where the typed getter came; this is the
// only one Android 12 has.
@Suppress("DEPRECATION")
private fun <T : Parcelable> Intent.untypedParcelable(name: String): T? = getParcelableExtra(name)
