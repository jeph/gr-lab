package io.jeph.grphoto

import android.content.Context
import android.net.ConnectivityManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.Socket
import java.net.SocketException
import java.net.UnknownHostException
import javax.net.SocketFactory
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import org.maplibre.android.MapLibre
import org.maplibre.android.module.http.HttpRequestUtil

/**
 * `io.jeph.grphoto/map`: sends the map's requests over the phone's internet
 * connection.
 *
 * While GR Photo is on a camera's Wi-Fi its whole process is bound to that
 * network (`WifiChannel` in gr_camera), which leads to the camera and
 * nowhere else, so MapLibre's requests for its tiles would go there and
 * fail. `useInternet`, which Dart calls before it shows a map, gives
 * MapLibre an HTTP client that opens every connection and looks every name
 * up on the phone's default network instead: mobile data, or a Wi-Fi the
 * phone keeps beside the camera's. A socket made by a network's own factory
 * is on that network whatever the process is bound to. Android does not
 * make the camera's network the default one, as GR Photo asks for it
 * without internet. With no default network a request fails at once and the
 * map stays empty.
 *
 * The client is MapLibre's for as long as the process lives, so it is made
 * once. MapLibre is started for it, which loads its native library: the
 * reason this waits for the first map instead of running with the app.
 */
object MapNetwork {
    /** MapLibre's own limit of requests to one host at a time. */
    private const val REQUESTS_PER_HOST = 20

    private var installed = false

    /** The channel on [messenger], which answers as long as its engine lives. */
    fun register(context: Context, messenger: BinaryMessenger): MethodChannel {
        val channel = MethodChannel(messenger, "io.jeph.grphoto/map")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "useInternet") {
                useInternet(context)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        return channel
    }

    private fun useInternet(context: Context) {
        if (installed) return
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        // Setting MapLibre's HTTP client needs MapLibre started.
        MapLibre.getInstance(context)
        HttpRequestUtil.setOkHttpClient(
            OkHttpClient.Builder()
                .dispatcher(Dispatcher().apply { maxRequestsPerHost = REQUESTS_PER_HOST })
                .socketFactory(DefaultNetworkSockets(connectivity))
                .dns { host ->
                    val network = connectivity.activeNetwork ?: throw UnknownHostException(NO_INTERNET)
                    network.getAllByName(host).toList()
                }
                .build(),
        )
        installed = true
    }
}

private const val NO_INTERNET = "The phone has no internet connection"

/** Sockets on the phone's default network as it is when each is made. */
private class DefaultNetworkSockets(private val connectivity: ConnectivityManager) : SocketFactory() {
    private val current: SocketFactory
        get() = connectivity.activeNetwork?.socketFactory ?: throw SocketException(NO_INTERNET)

    override fun createSocket(): Socket = current.createSocket()

    override fun createSocket(host: String, port: Int): Socket = current.createSocket(host, port)

    override fun createSocket(host: String, port: Int, localHost: InetAddress, localPort: Int): Socket =
        current.createSocket(host, port, localHost, localPort)

    override fun createSocket(host: InetAddress, port: Int): Socket = current.createSocket(host, port)

    override fun createSocket(address: InetAddress, port: Int, localAddress: InetAddress, localPort: Int): Socket =
        current.createSocket(address, port, localAddress, localPort)
}
