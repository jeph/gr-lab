import Flutter

/// `io.jeph.grphoto/location`: the phone's location for live geotagging and
/// for the location history, served by [PhoneLocator].
///
/// iOS shows no notice of GR Photo's own while a run is held, so `holdRun`
/// uses none of its arguments (the notice texts, Android's notification
/// channel name, `awake`: iOS has no wake lock, and an app that is located
/// keeps running), and `runStopped` is never sent. iOS has no setting that
/// exempts an app from being suspended, so `backgroundUnrestricted` and its
/// request answer that nothing is left to allow. `openSettings` opens GR
/// Photo's page of the Settings app for either page, because iOS lets no app
/// open its Location Services switch.
final class LocationPlugin {
  private let channel: FlutterMethodChannel
  private let locator = PhoneLocator.shared

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "io.jeph.grphoto/location", binaryMessenger: messenger)
    locator.dart.attach(channel)
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
    locator.engineDetached(channel)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    locator.dart.heardFromDart()
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "access":
      locator.access { result($0.map) }
    case "requestWhileInUse":
      locator.requestWhileInUse { result($0.map) }
    case "requestAlways":
      locator.requestAlways { result($0.map) }
    case "openSettings":
      locator.openSettings()
      result(nil)
    case "startUpdates":
      locator.startUpdates()
      result(nil)
    case "stopUpdates":
      locator.stopUpdates()
      result(nil)
    case "current":
      guard let timeoutMs = (args?["timeoutMs"] as? NSNumber)?.doubleValue else {
        result(FlutterError(code: "invalid", message: "current needs timeoutMs", details: nil))
        return
      }
      locator.current(timeout: timeoutMs / 1000) { result($0?.map) }
    case "holdRun":
      locator.holdRun { result($0.map(Self.error)) }
    case "releaseRun":
      locator.releaseRun()
      result(nil)
    case "backgroundUnrestricted", "requestBackgroundUnrestricted":
      result(true)
    case "setHistory":
      guard let enabled = args?["enabled"] as? Bool else {
        result(FlutterError(code: "invalid", message: "setHistory needs enabled", details: nil))
        return
      }
      locator.setHistory(enabled: enabled)
      result(nil)
    case "takeHistory":
      result(locator.takeHistory().map(\.map))
    case "setLogging":
      locator.dart.setLogging(args?["enabled"] as? Bool ?? false)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func error(_ refusal: PhoneLocator.RunRefusal) -> FlutterError {
    switch refusal {
    case .background:
      return FlutterError(
        code: "background",
        message: "iOS starts locating off screen only with Always permission", details: nil)
    case .noAccess:
      return FlutterError(
        code: "noAccess", message: "location is not allowed or is off", details: nil)
    case .failed(let message):
      return FlutterError(code: "failed", message: message, details: nil)
    }
  }
}
