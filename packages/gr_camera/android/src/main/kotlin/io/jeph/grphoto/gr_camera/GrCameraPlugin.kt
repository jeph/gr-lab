package io.jeph.grphoto.gr_camera

import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Registers the camera layer's native code: the camera Wi-Fi join
 * ([WifiChannel], `io.jeph.grphoto/wifi`), the phone's location
 * ([LocationChannel], `io.jeph.grphoto/location`) and the power-on watch
 * ([WatchChannel], `io.jeph.grphoto/watch`).
 *
 * [WifiChannel] needs to know when the app's activity is in front: Android
 * only joins camera networks for the foreground app, and its approval
 * screen pauses the activity. [LocationChannel] reads the location access
 * again on every resume, since the user changes it in the system settings.
 * The activity's resume and pause reach them through the application's
 * lifecycle callbacks, filtered to the activity this engine is attached
 * to.
 *
 * The engine can run with no activity at all (started for a camera that
 * came on with the app closed, [GeotagHost]): the location and watch
 * channels work without one, and get the activity for their permission
 * prompts and Android's association dialog while there is one.
 */
class GrCameraPlugin : FlutterPlugin, ActivityAware {
    private var wifi: WifiChannel? = null
    private var location: LocationChannel? = null
    private var watch: WatchChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var activity: Activity? = null

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(a: Activity) {
            if (a !== activity) return
            wifi?.onResume()
            location?.onResume()
        }

        override fun onActivityPaused(a: Activity) {
            if (a !== activity) return
            wifi?.onPause()
            location?.onPause()
        }

        override fun onActivityCreated(a: Activity, state: Bundle?) {}

        override fun onActivityStarted(a: Activity) {}

        override fun onActivityStopped(a: Activity) {}

        override fun onActivitySaveInstanceState(a: Activity, state: Bundle) {}

        override fun onActivityDestroyed(a: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        wifi = WifiChannel(binding.applicationContext, binding.binaryMessenger)
        location = LocationChannel(binding.applicationContext, binding.binaryMessenger)
        watch = WatchChannel(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        wifi?.dispose()
        wifi = null
        location?.dispose()
        location = null
        watch?.dispose()
        watch = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val a = binding.activity
        activity = a
        activityBinding = binding
        a.application.registerActivityLifecycleCallbacks(lifecycle)
        location?.let {
            binding.addRequestPermissionsResultListener(it)
            it.onActivity(a)
        }
        watch?.let {
            binding.addActivityResultListener(it)
            it.onActivity(a)
        }
    }

    override fun onDetachedFromActivity() {
        activity?.application?.unregisterActivityLifecycleCallbacks(lifecycle)
        activity = null
        val binding = activityBinding
        activityBinding = null
        location?.let {
            binding?.removeRequestPermissionsResultListener(it)
            it.onActivity(null)
        }
        watch?.let {
            binding?.removeActivityResultListener(it)
            it.onActivity(null)
        }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
}
