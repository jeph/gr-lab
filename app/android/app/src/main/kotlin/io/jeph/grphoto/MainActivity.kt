package io.jeph.grphoto

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The app's screen. It shows the UI of the app's one Flutter engine
 * ([AppEngine]), which may be running already (live geotagging started it
 * with the app closed) and may outlive this activity (a geotagging run is
 * held). The channels that need an activity live as long as it is
 * attached.
 */
class MainActivity : FlutterActivity() {
    private var media: MediaChannel? = null
    private var downloads: DownloadChannel? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        AppEngine.obtain(context, flutterShellArgs.toArray())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppEngine.attached(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        media = MediaChannel(applicationContext, messenger)
        downloads = DownloadChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        media?.dispose()
        media = null
        downloads?.dispose()
        downloads = null
        AppEngine.detached(this)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Finished for good (swiped away, or the back button at the first
        // screen), not destroyed by Android to be created again.
        if (isFinishing) AppEngine.releaseIfUnused()
    }
}
