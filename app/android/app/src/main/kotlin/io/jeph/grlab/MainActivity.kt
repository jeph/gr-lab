package io.jeph.grlab

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var media: MediaChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        media = MediaChannel(applicationContext, messenger)
        // The name the camera shows under Paired Devices: the user-set device
        // name where there is one, otherwise the model.
        MethodChannel(messenger, "io.jeph.grlab/device").setMethodCallHandler { call, result ->
            if (call.method == "name") {
                result.success(Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        media?.dispose()
        media = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
