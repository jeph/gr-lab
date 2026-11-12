package io.jeph.grphoto.gr_camera

import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * Registers the camera layer's native code: the camera Wi-Fi join
 * ([WifiChannel], `io.jeph.grphoto/wifi`) and the phone's position for
 * geotagging ([LocationChannel], `io.jeph.grphoto/location`).
 *
 * [WifiChannel] needs to know when the app's activity is in front: Android
 * only joins camera networks for the foreground app, and its approval
 * screen pauses the activity. The activity's resume and pause reach it
 * through the application's lifecycle callbacks, filtered to the activity
 * this engine is attached to.
 *
 * [LocationChannel] needs the activity itself, to show Android's location
 * permission prompt, and the prompt's answer, which Android delivers to
 * the activity and the activity binding passes on here.
 */
class GrCameraPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private var wifi: WifiChannel? = null
    private var location: LocationChannel? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(a: Activity) {
            if (a === activity) wifi?.onResume()
        }

        override fun onActivityPaused(a: Activity) {
            if (a === activity) wifi?.onPause()
        }

        override fun onActivityCreated(a: Activity, state: Bundle?) {}

        override fun onActivityStarted(a: Activity) {}

        override fun onActivityStopped(a: Activity) {}

        override fun onActivitySaveInstanceState(a: Activity, state: Bundle) {}

        override fun onActivityDestroyed(a: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        wifi = WifiChannel(binding.applicationContext, binding.binaryMessenger)
        location = LocationChannel(binding.applicationContext, binding.binaryMessenger).also {
            it.activity = activity
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        wifi?.dispose()
        wifi = null
        location?.dispose()
        location = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val a = binding.activity
        activity = a
        activityBinding = binding
        location?.activity = a
        a.application.registerActivityLifecycleCallbacks(lifecycle)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity?.application?.unregisterActivityLifecycleCallbacks(lifecycle)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        location?.activity = null
        activity = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        return location?.onRequestPermissionsResult(requestCode, grantResults) ?: false
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
}
