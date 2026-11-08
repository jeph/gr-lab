import Flutter
import NetworkExtension

/// `io.jeph.grlab/wifi`: joins the camera access point with a persistent
/// `NEHotspotConfiguration`. `joinOnce = false` keeps the association while
/// the app is in the background; `leave` removes the configuration again.
/// iOS chooses WPA2 or WPA3 itself, so the requested security is unused.
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

  private var pending: Attempt?
  /// The SSID whose configuration this app installed, removed by `leave`.
  private var configuredSsid: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.jeph.grlab/wifi", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(WifiPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "join":
      join(call.arguments as? [String: Any], result: result)
    case "currentSsid":
      NEHotspotNetwork.fetchCurrent { network in
        DispatchQueue.main.async { result(network?.ssid) }
      }
    case "leave":
      settle(pending, FlutterError(
        code: "cancelled", message: "left the camera network during the join", details: nil))
      if let ssid = configuredSsid {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
      }
      configuredSsid = nil
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

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { [weak self] in
      self?.settle(attempt, FlutterError(
        code: "timeout", message: "\"\(ssid)\" did not connect within \(timeoutMs) ms",
        details: nil))
    }

    let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
    configuration.joinOnce = false
    NEHotspotConfigurationManager.shared.apply(configuration) { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        let failure = (error as NSError?).flatMap { Self.isAlreadyAssociated($0) ? nil : $0 }
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
          NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: previous)
        }
        self.configuredSsid = ssid
        self.awaitAssociation(attempt)
      }
    }
  }

  /// Removes a configuration installed for an abandoned join unless a live
  /// join or the current association uses the same SSID.
  private func discardStaleConfiguration(_ ssid: String) {
    guard pending?.ssid != ssid, configuredSsid != ssid else { return }
    NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
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
          self.settle(attempt, nil)
          return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
          self?.awaitAssociation(attempt)
        }
      }
    }
  }

  private func settle(_ attempt: Attempt?, _ error: FlutterError?) {
    guard let attempt, pending === attempt else { return }
    pending = nil
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
        code: "background", message: "iOS only joins camera networks while GR Lab is open",
        details: nil)
    default:
      return FlutterError(code: "failed", message: error.localizedDescription, details: nil)
    }
  }
}
