import Flutter

/// Registers the camera layer's native code: the camera Wi-Fi join
/// ([WifiPlugin], `io.jeph.grphoto/wifi`), the phone's location
/// ([LocationPlugin], `io.jeph.grphoto/location`) and the power-on watch
/// ([WatchPlugin], `io.jeph.grphoto/watch`).
///
/// The location and the watch outlive Flutter engines
/// ([GrCameraBackground]), so each engine's channels are detached from them
/// when it goes away.
public final class GrCameraPlugin: NSObject, FlutterPlugin {
  private let location: LocationPlugin
  private let watch: WatchPlugin

  private init(messenger: FlutterBinaryMessenger) {
    location = LocationPlugin(messenger: messenger)
    watch = WatchPlugin(messenger: messenger)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    WifiPlugin.register(with: registrar)
    // An engine tells only the plugin it published that it is going away.
    registrar.publish(GrCameraPlugin(messenger: registrar.messenger()))
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    location.detach()
    watch.detach()
  }
}
