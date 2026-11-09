import Flutter

/// Registers the camera layer's native code: the camera Wi-Fi join
/// ([WifiPlugin], `io.jeph.grlab/wifi`).
public final class GrCameraPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    WifiPlugin.register(with: registrar)
  }
}
