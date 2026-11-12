import Flutter

/// Registers the camera layer's native code: the camera Wi-Fi join
/// ([WifiPlugin], `io.jeph.grphoto/wifi`) and the phone's location
/// ([LocationPlugin], `io.jeph.grphoto/location`).
///
/// The location outlives Flutter engines ([GrCameraBackground]), so each
/// engine's channel is detached from it when the engine goes away.
public final class GrCameraPlugin: NSObject, FlutterPlugin {
  private let location: LocationPlugin

  private init(messenger: FlutterBinaryMessenger) {
    location = LocationPlugin(messenger: messenger)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    WifiPlugin.register(with: registrar)
    // An engine tells only the plugin it published that it is going away.
    registrar.publish(GrCameraPlugin(messenger: registrar.messenger()))
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    location.detach()
  }
}
