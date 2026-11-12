package io.jeph.grphoto.gr_camera

/**
 * What the plugin needs from the app that hosts it, so live geotagging
 * carries on after the app's task is swiped away.
 *
 * The camera protocol is Dart, so a run of [GeotagService] is only worth
 * something while the Flutter engine that holds it lives. The host keeps
 * its engine for as long as [runHeld] is true, also with no activity, and
 * is told through [runEnded] when it no longer has to.
 *
 * Everything here is used on the main thread.
 */
object GeotagHost {
    /**
     * A run ended (released by the Dart side or stopped from the
     * notification): an engine nothing else needs can go. Called from a
     * posted task, never from inside a method-channel handler of that
     * engine. The host sets it before its engine can hold a run.
     */
    var runEnded: (() -> Unit)? = null

    /** The Dart side holds a run: [GeotagService] runs or is starting. */
    val runHeld: Boolean
        get() = GeotagService.held
}
