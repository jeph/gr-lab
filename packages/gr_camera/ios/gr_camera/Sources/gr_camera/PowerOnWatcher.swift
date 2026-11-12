import CoreBluetooth
import Flutter
import UIKit

/// Notices a paired camera being switched on, behind `io.jeph.grphoto/watch`
/// ([WatchPlugin]): a Bluetooth scan for the Camera Information service,
/// which a camera advertises only in its on state (off, it advertises Client
/// Registration instead; research/camera-models.md §4.1).
///
/// The scan belongs to a central manager of its own with a restore
/// identifier, so iOS keeps scanning while GR Photo is suspended or was
/// ended by the system, and wakes or starts it in the background for a
/// camera it finds (Apple, "Core Bluetooth Background Processing for iOS
/// Apps"). The manager, which makes iOS ask for the Bluetooth permission, is
/// created only once there is a camera to watch.
///
/// A scan in the background reports each camera once, so the same list
/// watched again starts a new scan, which reports a camera that went off
/// and came on again.
///
/// The watched cameras are CoreBluetooth peripheral identifiers. They are
/// the ones the app's Bluetooth plugin uses: iOS gives one app the same
/// identifier for a peripheral in every central manager. Everything runs on
/// the main queue.
final class PowerOnWatcher: NSObject, CBCentralManagerDelegate {
  static let shared = PowerOnWatcher()

  private static let state = StateFile(name: "watch")
  private static let watchedKey = "deviceIds"
  private static let sightingsKey = "launchSightings"

  private static let cameraInformation = CBUUID(string: "9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1")

  /// Has to be the same at every launch for iOS to hand the scan back.
  private static let restoreIdentifier = "io.jeph.grphoto.power-on-watch"

  /// How long a sighting keeps the app running in the background, so Dart
  /// can link the camera and start locating; a woken app otherwise gets
  /// about 10 s (the same Apple guide).
  private static let wakeTime: TimeInterval = 25

  /// iOS scans for a suspended or ended app only when it declares the
  /// `bluetooth-central` background mode.
  static var supported: Bool {
    GrCameraBackground.declaredModes.contains("bluetooth-central")
  }

  /// Takes the scan up again when the app is launched, with or without a
  /// Flutter engine, if cameras are watched.
  static func resumeIfInUse() {
    state.reload()
    guard !state.strings(watchedKey).isEmpty else { return }
    shared.resume()
  }

  let dart = DartLink(category: "watch")

  private var central: CBCentralManager?

  /// The watched cameras by peripheral identifier, each with the device id
  /// as Dart wrote it.
  private var watched: [UUID: String] = [:]

  private var wakeTask: UIBackgroundTaskIdentifier = .invalid

  private override init() {
    super.init()
    resume()
  }

  private func log(_ message: String) {
    dart.log(message)
  }

  /// The engine of `channel` is gone; the watch goes on without it.
  func engineDetached(_ channel: FlutterMethodChannel) {
    dart.detach(channel)
  }

  private func resume() {
    watched = Self.index(Self.state.strings(Self.watchedKey))
    if central == nil, !watched.isEmpty { createCentral() }
  }

  private static func index(_ deviceIds: [String]) -> [UUID: String] {
    var index: [UUID: String] = [:]
    for deviceId in deviceIds {
      guard let identifier = UUID(uuidString: deviceId) else { continue }
      index[identifier] = deviceId
    }
    return index
  }

  /// Replaces the watched cameras and starts the scan afresh; an empty list
  /// stops it.
  func watch(_ deviceIds: [String]) {
    remember(deviceIds, for: Self.watchedKey)
    watched = Self.index(deviceIds)
    log("watching \(watched.count) camera(s): \(deviceIds.joined(separator: ", "))")
    guard let central else {
      // The scan starts when the new manager reports Bluetooth on.
      if !watched.isEmpty { createCentral() }
      return
    }
    scan(central)
  }

  /// The cameras seen on while no Dart side listened, handed over once.
  func takeLaunchSightings() -> [String] {
    let sightings = Self.state.strings(Self.sightingsKey)
    if !sightings.isEmpty { remember([String](), for: Self.sightingsKey) }
    return sightings
  }

  private func createCentral() {
    var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: false]
    // iOS raises an exception for a restore identifier without the
    // background mode.
    if Self.supported {
      options[CBCentralManagerOptionRestoreIdentifierKey] = Self.restoreIdentifier
    }
    central = CBCentralManager(delegate: self, queue: nil, options: options)
  }

  private func scan(_ central: CBCentralManager) {
    guard central.state == .poweredOn else {
      log("Bluetooth state \(central.state.rawValue); the scan starts when it is on")
      return
    }
    // Stopping first makes iOS report again a camera the last scan reported.
    central.stopScan()
    guard !watched.isEmpty else {
      log("scan stopped")
      return
    }
    // The scan filters on the service alone: it is in the primary
    // advertising packet, while the manufacturer data comes in the scan
    // response, which a background scan may not get.
    central.scanForPeripherals(withServices: [Self.cameraInformation], options: nil)
    log("scanning for cameras that are on")
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    log("Bluetooth state \(central.state.rawValue)")
    // iOS drops every scan when Bluetooth goes off, and a restored one
    // would not report a camera it reported before.
    if central.state == .poweredOn { scan(central) }
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    let services = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] ?? []
    log("iOS restored the scan for \(services.map(\.uuidString).joined(separator: ", "))")
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    guard let deviceId = watched[peripheral.identifier] else { return }
    let power = Self.powerTag(advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
    log(
      "\(deviceId) advertises Camera Information, rssi \(RSSI), "
        + "power tag \(power.map { "\($0)" } ?? "absent")")
    // iOS can match on services it remembers from an earlier packet.
    guard power != 0 else { return }
    report(deviceId)
  }

  /// Tag `03` of the Ricoh manufacturer data (company `0x065F`, then
  /// `DA 01 <model> 02 <serial u32 LE> 03 <power>`): 1 on, 0 off. Nil when
  /// the data is absent or not in that form.
  private static func powerTag(_ data: Data?) -> UInt8? {
    guard let data, data.count >= 12 else { return nil }
    let bytes = [UInt8](data)
    guard bytes[0] == 0x5F, bytes[1] == 0x06, bytes[2] == 0xDA, bytes[3] == 0x01,
      bytes[5] == 0x02, bytes[10] == 0x03
    else { return nil }
    return bytes[11]
  }

  private func report(_ deviceId: String) {
    if dart.send("seenOn", ["deviceId": deviceId]) {
      stayAwake()
      return
    }
    var sightings = Self.state.strings(Self.sightingsKey)
    if !sightings.contains(deviceId) {
      sightings.append(deviceId)
      remember(sightings, for: Self.sightingsKey)
      log("no Dart side listens; \(deviceId) kept as a launch sighting")
    }
    // An engine whose Dart side has not called in yet takes the sighting
    // when it does. With no engine (iOS started the app in the background,
    // without a scene) the Dart side is started for it.
    guard !dart.attached else { return }
    log("no Flutter engine runs; starting the Dart side")
    stayAwake()
    GrCameraBackground.startDart?()
  }

  private func stayAwake() {
    let application = UIApplication.shared
    guard application.applicationState == .background, wakeTask == .invalid else { return }
    let task = application.beginBackgroundTask(withName: "GR Photo camera switched on") {
      [weak self] in self?.endWake()
    }
    wakeTask = task
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeTime) { [weak self] in
      guard let self, self.wakeTask == task else { return }
      self.endWake()
    }
  }

  private func endWake() {
    guard wakeTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(wakeTask)
    wakeTask = .invalid
  }

  private func remember(_ value: Any, for key: String) {
    do {
      try Self.state.set(value, for: key)
    } catch {
      log("could not save \(key): \(error)")
    }
  }
}
