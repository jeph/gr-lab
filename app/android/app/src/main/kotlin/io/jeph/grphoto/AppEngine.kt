package io.jeph.grphoto

import android.content.Context
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.jeph.grphoto.gr_camera.GeotagHost

/**
 * The one Flutter engine of the app, which outlives its screen while live
 * geotagging runs.
 *
 * The camera protocol is Dart, so a geotagging run carries on after the
 * app's task is swiped away only if the engine does. [MainActivity]
 * therefore does not own its engine: it is made here when the user opens
 * the app, with the application's context, with every plugin registered,
 * and running the app's `main`. When the user opens the app again while a
 * run kept the engine, the new activity attaches to that same engine
 * instead of starting a second copy of the app that would talk to the same
 * camera.
 *
 * The engine lasts as long as something needs it: an attached activity, or
 * a run of the geotagging service ([GeotagHost.runHeld]). When the
 * activity is finished and no run is held, or a run ends with no activity
 * attached, [releaseIfUnused] destroys it, so swiping the app away ends
 * Dart as it did when the activity owned the engine. An activity that
 * Android destroyed to get memory back leaves the engine alone, and the
 * app is as the user left it when they return.
 *
 * Everything here runs on the main thread.
 */
object AppEngine {
    private const val ENGINE_ID = "io.jeph.grphoto"

    private var attachedActivity: MainActivity? = null
    private var device: MethodChannel? = null

    /**
     * The engine, created and started when there is none. [dartVmArgs] are
     * the launch flags of the activity that starts it (`flutter run`
     * passes its debugging flags that way); they have no effect on an
     * engine that exists.
     */
    fun obtain(context: Context, dartVmArgs: Array<String>): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        // Set before the engine's Dart code can hold a run.
        GeotagHost.runEnded = { releaseIfUnused() }
        val engine = FlutterEngine(app, dartVmArgs)
        registerDeviceChannel(app, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put(ENGINE_ID, engine)
        return engine
    }

    /** [activity] shows the engine's UI now. */
    fun attached(activity: MainActivity) {
        attachedActivity = activity
    }

    /** [activity] no longer shows the engine's UI. */
    fun detached(activity: MainActivity) {
        // A new activity can attach before the old one is told to let go.
        if (attachedActivity === activity) attachedActivity = null
    }

    /** Destroys the engine when no activity is attached and no run is held. */
    fun releaseIfUnused() {
        if (attachedActivity != null || GeotagHost.runHeld) return
        val cache = FlutterEngineCache.getInstance()
        val engine = cache.get(ENGINE_ID) ?: return
        cache.remove(ENGINE_ID)
        device?.setMethodCallHandler(null)
        device = null
        engine.destroy()
    }

    /**
     * `io.jeph.grphoto/device`: the name the camera shows under Paired
     * Devices, which is the user-set device name where there is one,
     * otherwise the model.
     */
    private fun registerDeviceChannel(context: Context, engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "io.jeph.grphoto/device")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "name") {
                result.success(
                    Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL,
                )
            } else {
                result.notImplemented()
            }
        }
        device = channel
    }
}
