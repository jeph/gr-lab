import Flutter

/// `io.jeph.grphoto/watch`: the power-on watch, served by [PowerOnWatcher].
///
/// iOS needs no link between the app and a camera to scan for it, so
/// `associated` and `associate` always answer true and the camera names
/// `watch` carries (for Android's association prompt) are unused.
final class WatchPlugin {
  private let channel: FlutterMethodChannel
  private let watcher = PowerOnWatcher.shared

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "io.jeph.grphoto/watch", binaryMessenger: messenger)
    watcher.dart.attach(channel)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
  }

  /// The channel's engine is going away.
  func detach() {
    watcher.engineDetached(channel)
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    watcher.dart.heardFromDart()
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "supported":
      result(PowerOnWatcher.supported)
    case "associated", "associate":
      result(true)
    case "watch":
      guard let cameras = args?["cameras"] as? [[String: Any]] else {
        result(FlutterError(code: "invalid", message: "watch needs cameras", details: nil))
        return
      }
      watcher.watch(cameras.compactMap { $0["deviceId"] as? String })
      result(nil)
    case "takeLaunchSightings":
      result(watcher.takeLaunchSightings())
    case "setLogging":
      watcher.dart.setLogging(args?["enabled"] as? Bool ?? false)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
