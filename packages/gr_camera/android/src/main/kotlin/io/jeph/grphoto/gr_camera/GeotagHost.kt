package io.jeph.grphoto.gr_camera

import android.content.Context

/**
 * What the plugin needs from the app that hosts it, so live geotagging can
 * start with the app closed.
 *
 * The camera protocol is Dart. When the power-on watch ([WatchReceiver])
 * sees a camera come on and no Flutter engine runs, [GeotagService] asks
 * the host for one through [startEngine]; the host must hand its activity
 * the same engine later, so one copy of the app talks to the camera. The
 * host keeps that engine for as long as [runHeld] is true and is told
 * through [runEnded] when it no longer has to.
 *
 * The application sets both hooks in its `onCreate`, before any receiver or
 * service of the plugin runs. Everything here is used on the main thread.
 */
object GeotagHost {
    /**
     * Starts the app's Flutter engine and its Dart code without a screen;
     * nothing happens when it runs already.
     */
    var startEngine: ((Context) -> Unit)? = null

    /**
     * A run ended (released by the Dart side, stopped from the
     * notification, or never taken up after a start for a camera): an
     * engine nothing else needs can go. Called from a posted task, never
     * from inside a method-channel handler of that engine.
     */
    var runEnded: (() -> Unit)? = null

    /**
     * [GeotagService] runs or is starting, for a run the Dart side holds
     * or for a camera the Dart side has yet to take up.
     */
    val runHeld: Boolean
        get() = GeotagService.active
}
