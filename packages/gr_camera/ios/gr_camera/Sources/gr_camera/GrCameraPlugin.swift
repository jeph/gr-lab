import Flutter

/// Registers the camera layer's native code: the camera Wi-Fi join
/// ([WifiPlugin], `io.jeph.grphoto/wifi`) and the phone's position for
/// geotagging ([LocationPlugin], `io.jeph.grphoto/location`).
public final class GrCameraPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    WifiPlugin.register(with: registrar)
    LocationPlugin.register(with: registrar)
  }
}
