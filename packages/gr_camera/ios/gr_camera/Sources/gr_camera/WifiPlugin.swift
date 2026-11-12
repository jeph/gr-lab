import Flutter
import NetworkExtension
import os

/// `io.jeph.grphoto/wifi`: joins the camera access point with a persistent
/// `NEHotspotConfiguration`. `joinOnce = false` keeps the association while
/// the app is in the background; `leave` removes the configuration again.
/// iOS chooses WPA2 or WPA3 itself, so the requested security is unused.
///
/// Every log line also goes to Dart (`log`), which records it in the debug
/// log: the log a tester exports is then enough to see what iOS did during a
/// join. Nothing is logged while the app's debug logging is off
/// (`setLogging`).
final class WifiPlugin: NSObject, FlutterPlugin {
  /// One `join` call; a newer join, `leave` or the deadline settles it.
  private final class Attempt {
    let ssid: String
    let result: FlutterResult

    init(ssid: String, result: @escaping FlutterResult) {
      self.ssid = ssid
      self.result = result
    }
  }

  private static let logger = Logger(subsystem: "io.jeph.grphoto", category: "wifi")

  private let channel: FlutterMethodChannel
  private var pending: Attempt?
  /// The SSID whose configuration this app installed, removed by `leave`.
  private var configuredSsid: String?
  /// The join whose `apply` installed `configuredSsid`'s configuration.
  private var configurationOwner: Attempt?

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.jeph.grphoto/wifi", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(WifiPlugin(channel: channel), channel: channel)
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
    case "join":
      join(call.arguments as? [String: Any], result: result)
    case "setLogging":
      logging = call.arguments as? Bool ?? false
      result(nil)
    case "currentSsid":
      NEHotspotNetwork.fetchCurrent { network in
        DispatchQueue.main.async { result(network?.ssid) }
      }
    case "leave":
      settle(pending, FlutterError(
        code: "cancelled", message: "left the camera network during the join", details: nil))
      if let ssid = configuredSsid {
        log("removing the configuration of \"\(ssid)\"")
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
      }
      configuredSsid = nil
      configurationOwner = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func join(_ args: [String: Any]?, result: @escaping FlutterResult) {
    guard let ssid = args?["ssid"] as? String,
      let passphrase = args?["passphrase"] as? String,
      let timeoutMs = (args?["timeoutMs"] as? NSNumber)?.intValue
    else {
      result(FlutterError(
        code: "invalid", message: "join needs ssid, passphrase and timeoutMs", details: nil))
      return
    }
    settle(pending, FlutterError(
      code: "superseded", message: "a newer Wi-Fi join replaced this one", details: nil))
    let attempt = Attempt(ssid: ssid, result: result)
    pending = attempt
    log("applying a configuration for \"\(ssid)\"")

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { [weak self] in
      guard let self, self.pending === attempt else { return }
      self.settle(attempt, FlutterError(
        code: "timeout", message: "\"\(ssid)\" did not connect within \(timeoutMs) ms",
        details: nil))
      // Dart now treats the camera network as not joined; a configuration
      // left installed could still associate later.
      self.removeConfiguration(installedBy: attempt)
    }

    let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
    configuration.joinOnce = false
    NEHotspotConfigurationManager.shared.apply(configuration) { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        let failure = (error as NSError?).flatMap { Self.isAlreadyAssociated($0) ? nil : $0 }
        if let error = error as NSError? {
          self.log("apply for \"\(ssid)\": \(error.domain) \(error.code) \(error.localizedDescription)")
        } else {
          self.log("apply for \"\(ssid)\" succeeded")
        }
        guard self.pending === attempt else {
          // The join already ended (timeout, leave or a newer join), but iOS
          // installed the configuration anyway; nothing would remove it later.
          if failure == nil { self.discardStaleConfiguration(ssid) }
          return
        }
        if let failure {
          self.settle(attempt, Self.joinError(failure, ssid: ssid))
          return
        }
        if let previous = self.configuredSsid, previous != ssid {
          self.log("removing the configuration of \"\(previous)\"")
          NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: previous)
        }
        self.configuredSsid = ssid
        self.configurationOwner = attempt
        self.awaitAssociation(attempt)
      }
    }
  }

  /// Removes a configuration installed for an abandoned join unless a live
  /// join or the current association uses the same SSID.
  private func discardStaleConfiguration(_ ssid: String) {
    guard pending?.ssid != ssid, configuredSsid != ssid else { return }
    log("removing the stale configuration of \"\(ssid)\"")
    NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
  }

  /// Removes the configuration `attempt` installed, unless a newer join's
  /// successful `apply` has taken it over.
  private func removeConfiguration(installedBy attempt: Attempt) {
    guard configurationOwner === attempt, let ssid = configuredSsid else { return }
    log("removing the configuration of \"\(ssid)\" after its join timed out")
    NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    configuredSsid = nil
    configurationOwner = nil
  }

  /// `apply` can report success before (or without) the phone actually
  /// associating, e.g. when the AP is still booting, so wait until iOS
  /// reports the camera SSID. A nil answer means iOS will not say, in which
  /// case the session's HTTP identity check decides instead.
  private func awaitAssociation(_ attempt: Attempt) {
    NEHotspotNetwork.fetchCurrent { [weak self] network in
      DispatchQueue.main.async {
        guard let self, self.pending === attempt else { return }
        guard let current = network?.ssid, current != attempt.ssid else {
          self.log("current network \(network?.ssid ?? "unknown"); join of \"\(attempt.ssid)\" done")
          self.settle(attempt, nil)
          return
        }
        self.log("current network \"\(current)\"; waiting for \"\(attempt.ssid)\"")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
          self?.awaitAssociation(attempt)
        }
      }
    }
  }

  private func settle(_ attempt: Attempt?, _ error: FlutterError?) {
    guard let attempt, pending === attempt else { return }
    pending = nil
    if let error {
      log("join of \"\(attempt.ssid)\" ended: \(error.code): \(error.message ?? "")")
    }
    attempt.result(error)
  }

  private static func isAlreadyAssociated(_ error: NSError) -> Bool {
    error.domain == NEHotspotConfigurationErrorDomain
      && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
  }

  private static func joinError(_ error: NSError, ssid: String) -> FlutterError {
    guard error.domain == NEHotspotConfigurationErrorDomain,
      let code = NEHotspotConfigurationError(rawValue: error.code)
    else {
      return FlutterError(code: "failed", message: error.localizedDescription, details: nil)
    }
    switch code {
    case .userDenied:
      return FlutterError(
        code: "declined", message: "the request to join \"\(ssid)\" was declined",
        details: nil)
    case .invalid, .invalidSSID, .invalidWPAPassphrase, .invalidWEPPassphrase,
      .invalidEAPSettings, .invalidHS20Settings, .invalidHS20DomainName, .invalidSSIDPrefix:
      return FlutterError(
        code: "invalid", message: "iOS rejected the camera network settings (\(error.code))",
        details: nil)
    case .internal:
      // GR WORLD's ER_WF_007: a stale entry for the camera confuses iOS.
      return FlutterError(
        code: "failed",
        message: "iOS could not configure \"\(ssid)\"; forget it under Settings › Wi-Fi "
          + "and try again",
        details: nil)
    case .applicationIsNotInForeground:
      return FlutterError(
        code: "background", message: "iOS only joins camera networks while GR Photo is open",
        details: nil)
    default:
      return FlutterError(code: "failed", message: error.localizedDescription, details: nil)
    }
  }
}
