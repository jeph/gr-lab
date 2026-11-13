import CoreLocation
import Flutter
import UIKit

/// The phone's location service behind `io.jeph.grphoto/location`
/// ([LocationPlugin]), one for the whole process. It exists with or without
/// a Flutter engine, because iOS starts GR Photo in the background to
/// deliver a significant location change or a visit.
///
/// Three uses:
///
/// - Live positions for a camera that is on: standard location updates
///   (`startUpdates`, `current`), sent to Dart as they arrive.
/// - The run (`holdRun`): background location updates are allowed, so
///   updates that run go on with the app off screen. Besides iOS's own
///   location indicator the app's presenter shows the run's notice
///   ([GrCameraRun.noticePresenter], a Live Activity), whose Stop button
///   reaches Dart as `runStopped`. With While Using permission a
///   `CLBackgroundActivitySession` (iOS 17 and later) is held too, so
///   locating can start again from the background during the run; iOS shows
///   its blue indicator for as long as that session lasts, also while
///   nothing is located. With Always permission no session is needed, and
///   none is held, so the indicator shows only while the phone is located.
/// - The history (`setHistory`): significant location changes and visits,
///   which iOS delivers to a closed app that has Always permission. They go
///   to [LocationHistoryStore] until Dart takes them, and are never logged.
///
/// The history has a `CLLocationManager` of its own. A manager hands every
/// position to one delegate method without saying which service produced
/// it, so on a shared manager the history's positions could not be told
/// from the live ones, and recording them would depend on what Dart does
/// with live positions. With its own manager each position and visit of the
/// monitoring is stored, whatever live geotagging is doing. Everything runs
/// on the main queue.
final class PhoneLocator: NSObject, CLLocationManagerDelegate {
  /// What the user lets GR Photo do with the phone's location.
  struct Access {
    let status: CLAuthorizationStatus
    let precise: Bool
    let serviceOn: Bool

    var always: Bool { status == .authorizedAlways }

    /// iOS delivers positions, at least while the app is in use.
    var allowed: Bool { serviceOn && (always || status == .authorizedWhenInUse) }

    /// `permission`, `precise` and `service`. Not asked yet and restricted
    /// both count as denied.
    var map: [String: Any] {
      let permission =
        always ? "always" : status == .authorizedWhenInUse ? "whileInUse" : "denied"
      return ["permission": permission, "precise": precise, "service": serviceOn]
    }
  }

  /// Why `holdRun` held no run.
  enum RunRefusal {
    /// The app is off screen and iOS would not start locating from there.
    case background
    /// Location is not allowed, or is off for the whole phone.
    case noAccess
    case failed(String)
  }

  /// A permission request iOS has not answered yet.
  private final class Prompt {
    let from: CLAuthorizationStatus
    var completions: [(Access) -> Void]

    /// The app left the active state after the request, which is what the
    /// system's prompt does to it.
    var covered = false

    init(from: CLAuthorizationStatus, completion: @escaping (Access) -> Void) {
      self.from = from
      completions = [completion]
    }
  }

  /// One `current` call waiting for a position.
  private final class CurrentRequest {
    let completion: (LocationFix?) -> Void

    init(completion: @escaping (LocationFix?) -> Void) {
      self.completion = completion
    }
  }

  static let shared = PhoneLocator()

  private static let state = StateFile(name: "location")
  private static let historyKey = "history"

  /// The run whose Stop was pressed on a notice that outlived it.
  private static let runStopKey = "runStop"

  /// Time of the newest position stored from a location update: iOS hands
  /// its last known position over again whenever monitoring starts.
  private static let lastFixKey = "historyLastFixMs"

  /// Arrival time of the last visit stored: iOS reports a visit at arrival
  /// and again, with both times, at departure.
  private static let lastArrivalKey = "historyLastArrivalMs"

  /// A position older than this does not answer `current`.
  private static let currentMaxAge: TimeInterval = 10

  /// iOS shows its Always prompt once and ignores later requests without
  /// saying so. A request that has not covered the app after this long
  /// showed no prompt.
  private static let promptWait: TimeInterval = 1.5

  /// How long after its prompt closed a request waits for the authorization
  /// change. An answer that changes nothing ("Keep Only While Using") is
  /// never reported.
  private static let answerWait: TimeInterval = 1

  /// Starts the history's monitoring again when the app is launched, with
  /// or without a Flutter engine, if the history is on.
  static func resumeIfInUse() {
    state.reload()
    guard state.bool(historyKey) else { return }
    shared.applyHistory()
  }

  let dart = DartLink(category: "location")

  /// Live positions, the run and the permission requests.
  private let manager = CLLocationManager()

  /// Significant location changes and visits, for the history alone.
  private let monitor = CLLocationManager()
  private let history = LocationHistoryStore()

  private var prompt: Prompt?
  private var currentRequests: [CurrentRequest] = []

  /// Dart wants live positions (`startUpdates`).
  private var updatesWanted = false

  /// The updates were started where iOS starts them. False when they were
  /// asked for off screen with While Using permission and no background
  /// session: iOS then delivers nothing until the app is opened.
  private var updatesRunning = false

  private var runHeld = false

  /// The notice of the held run.
  private var runNotice: GrCameraRunNotice?

  /// Stop was pressed on the held run's notice, which took the notice away
  /// while the run stays held.
  private var runStopPressed = false

  /// A `CLBackgroundActivitySession` on iOS 17 and later.
  private var backgroundSession: AnyObject?

  /// Significant-change and visit monitoring was started by this process.
  private var historyMonitoring = false

  private override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    // A photographer standing still for minutes must not end the updates.
    manager.pausesLocationUpdatesAutomatically = false
    manager.activityType = .fitness
    monitor.delegate = self
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(willResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    applyHistory()
  }

  private func log(_ message: String) {
    dart.log(message)
  }

  // MARK: Engine

  /// The engine of `channel` is gone, and with it everything Dart held.
  func engineDetached(_ channel: FlutterMethodChannel) {
    guard dart.detach(channel) else { return }
    prompt = nil
    currentRequests = []
    stopUpdates()
    releaseRun()
  }

  // MARK: Access

  private var isAuthorized: Bool {
    let status = manager.authorizationStatus
    return status == .authorizedAlways || status == .authorizedWhenInUse
  }

  /// The access now. `locationServicesEnabled()` can block, and Apple asks
  /// for it off the main thread.
  func access(_ completion: @escaping (Access) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let serviceOn = CLLocationManager.locationServicesEnabled()
      DispatchQueue.main.async { [self] in
        completion(Access(
          status: manager.authorizationStatus,
          precise: manager.accuracyAuthorization == .fullAccuracy,
          serviceOn: serviceOn))
      }
    }
  }

  /// Asks for While Using permission; iOS prompts only while it was never
  /// asked.
  func requestWhileInUse(_ completion: @escaping (Access) -> Void) {
    request(completion, prompts: { $0 == .notDetermined }) {
      $0.requestWhenInUseAuthorization()
    }
  }

  /// Asks for Always permission; iOS prompts from never asked and, once,
  /// from While Using.
  func requestAlways(_ completion: @escaping (Access) -> Void) {
    request(completion, prompts: { $0 == .notDetermined || $0 == .authorizedWhenInUse }) {
      $0.requestAlwaysAuthorization()
    }
  }

  private func request(
    _ completion: @escaping (Access) -> Void,
    prompts: (CLAuthorizationStatus) -> Bool,
    ask: (CLLocationManager) -> Void
  ) {
    let status = manager.authorizationStatus
    // iOS prompts only over an app that is on screen.
    guard prompts(status), UIApplication.shared.applicationState == .active else {
      access(completion)
      return
    }
    if let prompt {
      prompt.completions.append(completion)
      return
    }
    let asked = Prompt(from: status, completion: completion)
    prompt = asked
    log("asking for permission from authorization \(status.rawValue)")
    ask(manager)
    // From never asked iOS always prompts, and the answer always arrives.
    guard status != .notDetermined else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.promptWait) { [weak self] in
      guard let self, self.prompt === asked, !asked.covered else { return }
      self.settlePrompt("iOS showed no prompt")
    }
  }

  private func settlePrompt(_ reason: String) {
    guard let asked = prompt else { return }
    prompt = nil
    log("permission request ended: \(reason)")
    access { access in
      for completion in asked.completions { completion(access) }
    }
  }

  private func sendAccess() {
    access { [self] in dart.send("accessChanged", $0.map) }
  }

  func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  @objc private func willResignActive() {
    prompt?.covered = true
  }

  @objc private func didBecomeActive() {
    if let asked = prompt, asked.covered {
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.answerWait) { [weak self] in
        guard let self, self.prompt === asked else { return }
        self.settlePrompt("GR Photo is active again")
      }
    }
    // Updates asked for off screen may not have started.
    applyUpdates()
    // Nor may the notice of a run held there have been shown.
    if let runNotice, !runStopPressed { GrCameraRun.noticePresenter?.show(runNotice) }
    sendAccess()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    // Both managers report the same change.
    guard manager === self.manager else { return }
    let status = manager.authorizationStatus
    let precise = manager.accuracyAuthorization == .fullAccuracy
    log("authorization \(status.rawValue), precise \(precise)")
    // iOS also calls this for a new manager, with nothing changed.
    if let prompt, prompt.from != status { settlePrompt("answered") }
    applyUpdates()
    applyHistory()
    sendAccess()
  }

  // MARK: Live positions

  /// iOS starts location updates here: on screen, with Always permission,
  /// or inside a background activity session.
  private var canStartLocating: Bool {
    UIApplication.shared.applicationState != .background
      || manager.authorizationStatus == .authorizedAlways || backgroundSession != nil
  }

  func startUpdates() {
    guard !updatesWanted else { return }
    updatesWanted = true
    applyUpdates()
  }

  func stopUpdates() {
    guard updatesWanted else { return }
    updatesWanted = false
    updatesRunning = false
    manager.stopUpdatingLocation()
    log("location updates stopped")
    // A `current` that waited for the next update needs its own request.
    if !currentRequests.isEmpty { manager.requestLocation() }
  }

  /// Starts the updates Dart wants when iOS allows them; safe to repeat.
  private func applyUpdates() {
    guard updatesWanted else { return }
    guard isAuthorized else {
      updatesRunning = false
      return
    }
    if !updatesRunning {
      updatesRunning = canStartLocating
      log(
        updatesRunning
          ? "location updates started"
          : "location updates asked for off screen without Always permission or a "
            + "background session; iOS starts them when GR Photo is opened")
    }
    manager.startUpdatingLocation()
  }

  /// One newly taken position, or nil after `timeout`.
  func current(timeout: TimeInterval, _ completion: @escaping (LocationFix?) -> Void) {
    guard isAuthorized else {
      completion(nil)
      return
    }
    let request = CurrentRequest(completion: completion)
    currentRequests.append(request)
    // While updates run their next position is the answer: iOS ignores
    // requestLocation() then, and starting updates cancels a pending one
    // (Apple's documentation of requestLocation()).
    if !updatesWanted { manager.requestLocation() }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self,
        let index = self.currentRequests.firstIndex(where: { $0 === request })
      else { return }
      self.currentRequests.remove(at: index)
      if self.currentRequests.isEmpty, !self.updatesWanted {
        // Cancels the pending requestLocation().
        self.manager.stopUpdatingLocation()
      }
      self.log("no new position within \(timeout) s")
      completion(nil)
    }
  }

  private func answerCurrentRequests(_ fix: LocationFix?) {
    let waiting = currentRequests
    currentRequests = []
    for request in waiting { request.completion(fix) }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    let fixes = locations.compactMap { LocationFix($0) }
    guard manager === self.manager else {
      recordLocations(fixes)
      return
    }
    let cutoff = LocationFix.milliseconds(Date().addingTimeInterval(-Self.currentMaxAge))
    for fix in fixes {
      if updatesWanted { dart.send("fix", fix.map) }
      if fix.timeMs >= cutoff, !currentRequests.isEmpty { answerCurrentRequests(fix) }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let error = error as NSError
    guard manager === self.manager else {
      log("history: monitoring failed: \(error.domain) \(error.code)")
      return
    }
    log("locating failed: \(error.domain) \(error.code)")
    // A failed requestLocation() is over; running updates keep trying.
    if !updatesWanted { answerCurrentRequests(nil) }
  }

  // MARK: Run

  /// Lets location updates go on with the app off screen, showing
  /// `notice`, or replaces the notice of the run already held.
  func holdRun(_ notice: GrCameraRunNotice, _ completion: @escaping (RunRefusal?) -> Void) {
    access { [self] access in
      if let refusal = holdRun(with: access) {
        releaseRun()
        completion(refusal)
        return
      }
      runNotice = notice
      runStopPressed = false
      GrCameraRun.noticePresenter?.show(notice)
      completion(nil)
    }
  }

  private func holdRun(with access: Access) -> RunRefusal? {
    guard access.allowed else { return .noAccess }
    // iOS ends an app that allows background location updates without
    // declaring the background mode.
    guard GrCameraBackground.declaredModes.contains("location") else {
      return .failed("UIBackgroundModes in Info.plist lacks location")
    }
    let onScreen = UIApplication.shared.applicationState != .background
    if access.always {
      // The session would show the blue indicator for the whole run.
      endBackgroundSession()
    } else if onScreen {
      // Only an app on screen can start a session.
      beginBackgroundSession()
    }
    // Updates already running in this run keep a While Using app in use.
    guard onScreen || access.always || backgroundSession != nil || (runHeld && updatesRunning)
    else { return .background }
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    if !runHeld {
      runHeld = true
      log("run held\(backgroundSession == nil ? "" : " with a background activity session")")
    }
    return nil
  }

  func releaseRun() {
    guard runHeld || backgroundSession != nil else { return }
    runHeld = false
    removeRunNotice()
    endBackgroundSession()
    manager.allowsBackgroundLocationUpdates = false
    manager.showsBackgroundLocationIndicator = false
    log("run released")
  }

  /// Stop was pressed on a notice of the run `run`.
  ///
  /// For the run held now the notice goes at once, and the run stays held
  /// until Dart releases it: Stop turns live geotagging off, which Dart has
  /// to save first, as on Android. With no Dart side to tell, the run ends
  /// here.
  ///
  /// Any other notice outlived its run: iOS ended GR Photo while it was
  /// suspended, and started it again for this Stop. The Stop is kept, across
  /// launches too, until Dart takes it (`takeRunStop`) and turns live
  /// geotagging off for that run's camera.
  func runStoppedByUser(_ run: String) {
    guard runHeld, let runNotice, runNotice.run == run else {
      log("run: Stop pressed on a notice that outlived its run")
      remember(run, for: Self.runStopKey)
      dart.send("runStopPending")
      return
    }
    guard !runStopPressed else { return }
    log("run: stopped from its notice")
    runStopPressed = true
    GrCameraRun.noticePresenter?.remove()
    if !dart.send("runStopped") { releaseRun() }
  }

  /// Hands over the run whose Stop was pressed on a notice that outlived
  /// it, and forgets it; nil when there is none.
  func takeRunStop() -> String? {
    guard let run = Self.state.string(Self.runStopKey) else { return nil }
    remember(nil, for: Self.runStopKey)
    return run
  }

  private func removeRunNotice() {
    guard runNotice != nil else { return }
    runNotice = nil
    runStopPressed = false
    GrCameraRun.noticePresenter?.remove()
  }

  private func beginBackgroundSession() {
    guard #available(iOS 17.0, *), backgroundSession == nil else { return }
    backgroundSession = CLBackgroundActivitySession()
  }

  private func endBackgroundSession() {
    guard #available(iOS 17.0, *),
      let session = backgroundSession as? CLBackgroundActivitySession
    else { return }
    session.invalidate()
    backgroundSession = nil
  }

  // MARK: History

  private var historyOn: Bool {
    Self.state.bool(Self.historyKey)
  }

  func setHistory(enabled: Bool) {
    remember(enabled, for: Self.historyKey)
    if enabled {
      applyHistory()
      return
    }
    // Unconditional, so monitoring an earlier launch started ends too.
    historyMonitoring = false
    monitor.stopMonitoringSignificantLocationChanges()
    monitor.stopMonitoringVisits()
    log("history recording off")
  }

  /// Monitors while the history is on and the permission is Always, the
  /// only level at which iOS delivers these events to an app off screen or
  /// closed. Safe to repeat.
  private func applyHistory() {
    let wanted = historyOn && manager.authorizationStatus == .authorizedAlways
    guard wanted != historyMonitoring else { return }
    historyMonitoring = wanted
    if wanted {
      if CLLocationManager.significantLocationChangeMonitoringAvailable() {
        monitor.startMonitoringSignificantLocationChanges()
      }
      monitor.startMonitoringVisits()
    } else {
      monitor.stopMonitoringSignificantLocationChanges()
      monitor.stopMonitoringVisits()
    }
    log("history recording \(wanted ? "started" : "stopped: the permission is not Always")")
  }

  /// Hands the recorded positions over, oldest first, and forgets them.
  func takeHistory() -> [LocationFix] {
    do {
      let fixes = try history.take()
      if !fixes.isEmpty { log("history: \(fixes.count) position(s) handed over") }
      return fixes
    } catch {
      log("history: could not read the store: \(error)")
      return []
    }
  }

  private func recordLocations(_ fixes: [LocationFix]) {
    guard historyOn else { return }
    let last = Self.state.int64(Self.lastFixKey) ?? .min
    let unseen = fixes.filter { $0.timeMs > last }
    guard let newest = unseen.map(\.timeMs).max() else { return }
    remember(NSNumber(value: newest), for: Self.lastFixKey)
    store(unseen)
  }

  /// A visit lasts from its arrival to its departure, so it is stored as a
  /// position at each of the two times iOS knows.
  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    // iOS delivers visits to every manager of the app.
    guard manager === monitor, historyOn, CLLocationCoordinate2DIsValid(visit.coordinate)
    else { return }
    var times: [Int64] = []
    if visit.arrivalDate != .distantPast {
      let arrival = LocationFix.milliseconds(visit.arrivalDate)
      if arrival != Self.state.int64(Self.lastArrivalKey) {
        times.append(arrival)
        remember(NSNumber(value: arrival), for: Self.lastArrivalKey)
      }
    }
    if visit.departureDate != .distantFuture {
      times.append(LocationFix.milliseconds(visit.departureDate))
    }
    let accuracy: Double? = visit.horizontalAccuracy >= 0 ? visit.horizontalAccuracy : nil
    store(times.map {
      LocationFix(
        latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude,
        accuracy: accuracy, altitude: nil, timeMs: $0)
    })
  }

  private func store(_ fixes: [LocationFix]) {
    guard !fixes.isEmpty else { return }
    do {
      try history.append(fixes, now: Date())
    } catch {
      log("history: could not store \(fixes.count) position(s): \(error)")
      return
    }
    log("history: \(fixes.count) position(s) stored")
    dart.send("historyPending")
  }

  private func remember(_ value: Any?, for key: String) {
    do {
      try Self.state.set(value, for: key)
    } catch {
      log("could not save \(key): \(error)")
    }
  }
}
