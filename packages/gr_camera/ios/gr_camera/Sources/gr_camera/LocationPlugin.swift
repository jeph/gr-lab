import CoreLocation
import Flutter
import UIKit
import os

/// `io.jeph.grphoto/location`: the phone's position, read with a
/// `CLLocationManager` to geotag a camera's pictures.
///
/// A run (`start` to `stop`) keeps location updates going with the app not
/// in front. That needs only "While Using the App" access, which is all
/// this class ever asks for, together with the `location` background mode
/// and `allowsBackgroundLocationUpdates`; iOS shows its own indicator while
/// it lasts. Where iOS cannot do what the channel describes:
///
/// - The notice texts of `start` (`title`, `text`, `stopLabel`,
///   `channelName`) are unused: iOS shows its own indicator and takes no
///   text for it.
/// - `stopRequested` is never sent: that indicator has no button that ends
///   the run.
/// - `start` never answers the error `background`: iOS does not tell a run
///   that it began with the app not in front; the updates then simply stop
///   arriving once the app is suspended.
/// - `openSettings` always opens the app's own settings page: iOS has no
///   public URL for the phone's location switch.
///
/// Every log line also goes to Dart (`log`), which records it in the debug
/// log. Nothing is logged while the app's debug logging is off
/// (`setLogging`).
final class LocationPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
  private enum Mode: String {
    case precise
    case idle
  }

  private static let logger = Logger(subsystem: "io.jeph.grphoto", category: "location")

  private let channel: FlutterMethodChannel
  /// Created on the main thread, so its delegate calls arrive there too.
  private let manager = CLLocationManager()

  /// Whether a run is under way.
  private var running = false
  private var mode = Mode.idle
  /// The least time between two fixes passed on in precise mode.
  private var interval: TimeInterval = 0
  /// When the last fix of this precise spell was passed on, on the
  /// `systemUptime` clock; nil until its first one.
  private var lastPreciseSendUptime: TimeInterval?
  /// The newest fix that arrived before [interval] was over, passed on
  /// once it is.
  private var heldFix: CLLocation?
  /// Counts the precise spells, so a wake-up scheduled in an earlier one
  /// does nothing.
  private var preciseSpell = 0
  /// Whether a wake-up for [heldFix] is scheduled in this spell.
  private var wakeUpScheduled = false
  /// The access last reported to Dart during this run, by `start` or by
  /// `accessChanged`.
  private var reportedAccess: String?
  /// The `requestAccess` calls waiting for the user to answer the prompt.
  private var pendingRequests: [FlutterResult] = []

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    manager.delegate = self
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.jeph.grphoto/location", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LocationPlugin(channel: channel), channel: channel)
  }

  /// The app's "Enable debug logging" setting, sent through `setLogging`
  /// when the engine starts and whenever it changes.
  private var logging = false

  /// Logs [message] to the unified log and to Dart while [logging] is on.
  /// Runs on the main queue, as every caller does.
  private func log(_ message: String) {
    guard logging else { return }
    Self.logger.info("\(message, privacy: .public)")
    channel.invokeMethod("log", arguments: message)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "access":
      fetchAccess { result($0) }
    case "requestAccess":
      requestAccess(result: result)
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        log("opening the app's settings page")
        UIApplication.shared.open(url)
      }
      result(nil)
    case "start":
      start(call.arguments as? [String: Any], result: result)
    case "setMode":
      setMode(call.arguments as? String, result: result)
    case "stop":
      stop()
      result(nil)
    case "setLogging":
      logging = call.arguments as? Bool ?? false
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Answers one of the channel's access strings on the main queue.
  /// `locationServicesEnabled()` can block, and iOS warns when it is called
  /// on the main thread, so it is read on a background queue.
  private func fetchAccess(_ completion: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let servicesEnabled = CLLocationManager.locationServicesEnabled()
      DispatchQueue.main.async {
        completion(self.access(servicesEnabled: servicesEnabled))
      }
    }
  }

  private func access(servicesEnabled: Bool) -> String {
    // With location off for every app, the status reads `.denied`.
    guard servicesEnabled else { return "off" }
    switch manager.authorizationStatus {
    case .notDetermined:
      return "undetermined"
    case .authorizedWhenInUse, .authorizedAlways:
      return manager.accuracyAuthorization == .reducedAccuracy ? "approximate" : "precise"
    case .denied, .restricted:
      return "blocked"
    @unknown default:
      return "blocked"
    }
  }

  /// Asks for "While Using the App" when iOS can still ask, and answers
  /// once `locationManagerDidChangeAuthorization` reports the user's
  /// choice. Never asks for "Always".
  private func requestAccess(result: @escaping FlutterResult) {
    fetchAccess { access in
      guard access == "undetermined" else {
        self.log("requestAccess: \(access), nothing to ask")
        result(access)
        return
      }
      self.log("requestAccess: asking for location while in use")
      self.pendingRequests.append(result)
      self.manager.requestWhenInUseAuthorization()
    }
  }

  /// Begins a run in idle mode, or changes the interval of the one under
  /// way. The notice texts in [args] are unused (see the class comment).
  private func start(_ args: [String: Any]?, result: @escaping FlutterResult) {
    guard let intervalMs = (args?["intervalMs"] as? NSNumber)?.intValue else {
      result(FlutterError(code: "invalid", message: "start needs intervalMs", details: nil))
      return
    }
    if running {
      interval = TimeInterval(intervalMs) / 1000
      log("start: run under way, interval now \(intervalMs) ms")
      result(nil)
      return
    }
    fetchAccess { access in
      guard access == "precise" || access == "approximate" else {
        self.log("start: refused, access is \(access)")
        result(FlutterError(
          code: "denied", message: "location access is \(access)", details: nil))
        return
      }
      self.interval = TimeInterval(intervalMs) / 1000
      // A second `start` may have begun the run while this one read the
      // access.
      if !self.running {
        self.beginRun(access: access)
        self.log("start: run begun in idle mode, interval \(intervalMs) ms, access \(access)")
      }
      result(nil)
    }
  }

  private func beginRun(access: String) {
    running = true
    reportedAccess = access
    // Needs the `location` background mode in the app's Info.plist.
    manager.allowsBackgroundLocationUpdates = true
    // A pause would end the updates that keep the app running, and with
    // "While Using the App" nothing could resume them in the background.
    manager.pausesLocationUpdatesAutomatically = false
    manager.showsBackgroundLocationIndicator = true
    // [design] The phone is carried by someone on foot with a camera.
    // [inferred] The activity type mostly steers automatic pauses, which
    // are off, so the choice should change little.
    manager.activityType = .fitness
    apply(.idle)
    manager.startUpdatingLocation()
  }

  private func setMode(_ name: String?, result: @escaping FlutterResult) {
    guard let name, let mode = Mode(rawValue: name) else {
      result(FlutterError(
        code: "invalid", message: "setMode needs \"precise\" or \"idle\"", details: nil))
      return
    }
    guard running else {
      result(FlutterError(code: "notRunning", message: "no run is under way", details: nil))
      return
    }
    if mode != self.mode {
      log("setMode: \(mode.rawValue)")
      apply(mode)
    }
    result(nil)
  }

  private func apply(_ mode: Mode) {
    self.mode = mode
    resetThrottle()
    switch mode {
    case .precise:
      manager.desiredAccuracy = kCLLocationAccuracyBest
      manager.distanceFilter = kCLDistanceFilterNone
    case .idle:
      // [design] Updates stay on while no camera wants fixes: location
      // updates that keep running are what keep the app alive with its
      // screen off, and it must stay alive to notice the camera coming
      // back. [inferred] from Apple's background location documentation,
      // not measured: the coarsest accuracy with a matching distance filter
      // is the cheapest setting that still does that.
      manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
      manager.distanceFilter = 3000
    }
  }

  private func stop() {
    guard running else { return }
    running = false
    reportedAccess = nil
    resetThrottle()
    manager.stopUpdatingLocation()
    manager.allowsBackgroundLocationUpdates = false
    log("stop: run ended")
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard running else { return }
    let valid = locations.filter { $0.horizontalAccuracy >= 0 }
    if valid.count < locations.count {
      log("skipped \(locations.count - valid.count) fix(es) without a valid position")
    }
    switch mode {
    case .idle:
      // Rare, so every one is passed on.
      valid.forEach(send)
    case .precise:
      // Only the newest of a delivery can be passed on.
      guard let newest = valid.last else { return }
      heldFix = newest
      passOnHeldFixWhenDue()
    }
  }

  /// Passes on [heldFix] at once when it is the first of its precise spell
  /// or [interval] has gone by since the last one, and otherwise when that
  /// time is up, unless a newer fix has replaced it by then. Dart so gets
  /// at most one fix per interval, and a fix that arrives a moment early
  /// is delayed instead of dropped, which would double the interval
  /// [design]. The time is measured on the monotonic uptime clock, not by
  /// the fixes' own times, which say nothing about when they are delivered.
  private func passOnHeldFixWhenDue() {
    guard let fix = heldFix else { return }
    let now = ProcessInfo.processInfo.systemUptime
    let wait = lastPreciseSendUptime.map { $0 + interval - now } ?? 0
    guard wait > 0 else {
      heldFix = nil
      lastPreciseSendUptime = now
      send(fix)
      return
    }
    guard !wakeUpScheduled else { return }
    wakeUpScheduled = true
    let spell = preciseSpell
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      guard let self, self.preciseSpell == spell else { return }
      self.wakeUpScheduled = false
      self.passOnHeldFixWhenDue()
    }
  }

  /// Forgets the precise spell under way: the next precise fix is the
  /// first of a new one.
  private func resetThrottle() {
    preciseSpell += 1
    wakeUpScheduled = false
    lastPreciseSendUptime = nil
    heldFix = nil
  }

  private func send(_ location: CLLocation) {
    let fix: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      // Above sea level; unknown unless the vertical accuracy is positive.
      "altitude": location.verticalAccuracy > 0 ? (location.altitude as Any) : NSNull(),
      "accuracy": location.horizontalAccuracy,
      "timeMs": Int64((location.timestamp.timeIntervalSince1970 * 1000).rounded()),
      "speed": location.speed >= 0 ? (location.speed as Any) : NSNull(),
    ]
    channel.invokeMethod("fix", arguments: fix)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let error = error as NSError
    log("location failed: \(error.domain) \(error.code) \(error.localizedDescription)")
    guard error.domain == kCLErrorDomain, error.code == CLError.Code.denied.rawValue else {
      return
    }
    fetchAccess { self.reportIfChanged($0) }
  }

  /// Also called once when the manager is created, and when location is
  /// turned on or off for every app.
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let answered = manager.authorizationStatus != .notDetermined
    fetchAccess { access in
      self.log("authorization changed: \(access)")
      if answered {
        let requests = self.pendingRequests
        self.pendingRequests = []
        requests.forEach { $0(access) }
      }
      self.reportIfChanged(access)
    }
  }

  /// Sends `accessChanged` when [access] differs from what Dart last heard
  /// during this run.
  private func reportIfChanged(_ access: String) {
    guard running, access != reportedAccess else { return }
    reportedAccess = access
    log("accessChanged: \(access)")
    channel.invokeMethod("accessChanged", arguments: access)
  }
}
