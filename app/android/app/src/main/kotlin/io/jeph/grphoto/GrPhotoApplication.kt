package io.jeph.grphoto

import android.app.Application
import io.jeph.grphoto.gr_camera.GeotagHost

/**
 * Tells the camera layer how to start the app's Dart code without a
 * screen, before any of its receivers or services runs: Android creates
 * the application first in every process it starts, also one started for
 * a broadcast.
 */
class GrPhotoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        GeotagHost.startEngine = { context -> AppEngine.obtain(context) }
        GeotagHost.runEnded = { AppEngine.releaseIfUnused() }
    }
}
