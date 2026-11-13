import Flutter

/// `io.jeph.grphoto/location`: the phone's location for live geotagging and
/// for the location history, served by [PhoneLocator].
///
/// While a run is held the app shows its notice as a Live Activity
/// ([GrCameraRun.noticePresenter]), and `runStopped` is sent when its Stop
/// button is pressed. A Live Activity can outlive the app; a Stop pressed on
/// one that did is announced with `runStopPending` and handed over by
/// `takeRunStop`. `holdRun` uses the notice's run, title, text and Stop
/// label and none of its other arguments (Android's notification channel
/// name, and `awake`: iOS has no wake lock, and an app that is located keeps
/// running). iOS has no setting that exempts an app from being suspended,
/// so `backgroundUnrestricted` and its request answer that nothing is left
/// to allow. `openSettings` opens GR Photo's page of the Settings app for
/// either page, because iOS lets no app open its Location Services switch.
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
    case "alwaysSettingsChoice":
      // iOS asks for Always in an alert over the app, which shows the
      // app's own reason: there is no settings page to name a choice of.
      result(nil)
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
      guard let run = args?["run"] as? String, let title = args?["title"] as? String,
        let text = args?["text"] as? String, let stopLabel = args?["stopLabel"] as? String
      else {
        result(
          FlutterError(
            code: "failed", message: "holdRun needs run, title, text and stopLabel", details: nil))
        return
      }
      let notice = GrCameraRunNotice(run: run, title: title, text: text, stopLabel: stopLabel)
      locator.holdRun(notice) { result($0.map(Self.error)) }
    case "releaseRun":
      locator.releaseRun()
      result(nil)
    case "takeRunStop":
      result(locator.takeRunStop())
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
