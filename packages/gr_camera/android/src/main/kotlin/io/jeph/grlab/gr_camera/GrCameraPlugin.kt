package io.jeph.grlab.gr_camera

import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Registers the camera layer's native code: the camera Wi-Fi join
 * ([WifiChannel], `io.jeph.grlab/wifi`).
 *
 * [WifiChannel] needs to know when the app's activity is in front: Android
 * only joins camera networks for the foreground app, and its approval
 * screen pauses the activity. The activity's resume and pause reach it
 * through the application's lifecycle callbacks, filtered to the activity
 * this engine is attached to.
 */
class GrCameraPlugin : FlutterPlugin, ActivityAware {
    private var wifi: WifiChannel? = null
    private var activity: Activity? = null

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
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        wifi?.dispose()
        wifi = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val a = binding.activity
        activity = a
        a.application.registerActivityLifecycleCallbacks(lifecycle)
    }

    override fun onDetachedFromActivity() {
        activity?.application?.unregisterActivityLifecycleCallbacks(lifecycle)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
}
