package io.jeph.grphoto.gr_camera

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Sets up again what Android forgets when the phone restarts, and may
 * forget when the app is updated: the location request of the history
 * ([HistoryRecorder]) and the scan of the power-on watch ([PowerOnScan]).
 * Both read what to do from the app's preferences; no Flutter engine is
 * started.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val app = context.applicationContext
        Logs.location.log(app, "history: setting up after $action")
        HistoryRecorder.sync(app)
        Logs.watch.log(app, "scan: setting up after $action")
        PowerOnScan.restart(app)
    }
}
