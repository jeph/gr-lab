import Flutter
import os

/// The Dart end of one method channel, for native code that exists with or
/// without a Flutter engine: iOS starts GR Photo in the background for a
/// location event before any engine, or with none at all.
///
/// Calls to Dart go out only once Dart has called in on the channel, because
/// a call sent before Dart listens is lost.
///
/// Log lines follow the Wi-Fi channel's rule: they go to the unified log and
/// to Dart (`log`) while the app's debug logging is on, and nowhere while it
/// is off. Until Dart has said which it is (`setLogging`), the newest lines
/// are held in memory, so that the log a tester exports also shows what the
/// native code did while no engine ran. Main queue only.
final class DartLink {
  private static let heldLineLimit = 200

  private let logger: Logger
  private var channel: FlutterMethodChannel?
  private var listening = false

  /// The app's "Enable debug logging" setting; nil until Dart has sent it.
  private var logging: Bool?
  private var heldLines: [String] = []

  init(category: String) {
    logger = Logger(subsystem: "io.jeph.grphoto", category: category)
  }

  /// A Flutter engine registered the channel; Dart is not listening yet.
  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    listening = false
    logging = nil
  }

  /// The engine of `channel` is gone. False when another engine's channel
  /// has taken its place.
  @discardableResult
  func detach(_ channel: FlutterMethodChannel) -> Bool {
    guard self.channel === channel else { return false }
    self.channel = nil
    listening = false
    logging = nil
    return true
  }

  /// Dart called a method on the channel, so its handler is set.
  func heardFromDart() {
    listening = true
  }

  /// Calls `method` in Dart; false when no Dart side listens.
  @discardableResult
  func send(_ method: String, _ arguments: Any? = nil) -> Bool {
    guard listening, let channel else { return false }
    channel.invokeMethod(method, arguments: arguments)
    return true
  }

  func setLogging(_ enabled: Bool) {
    logging = enabled
    let held = heldLines
    heldLines = []
    guard enabled else { return }
    for line in held { emit(line) }
  }

  func log(_ message: String) {
    if let logging {
      if logging { emit(message) }
      return
    }
    if heldLines.count == Self.heldLineLimit { heldLines.removeFirst() }
    // Held lines reach the log late, so each says when it was written.
    heldLines.append("[\(ISO8601DateFormatter().string(from: Date()))] \(message)")
  }

  private func emit(_ line: String) {
    logger.info("\(line, privacy: .public)")
    channel?.invokeMethod("log", arguments: line)
  }
}
