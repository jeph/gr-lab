import BackgroundTasks
import Flutter
import UIKit

/// `io.jeph.grlab/downloads`: keeps the download queue running after GR Lab
/// leaves the screen, as far as iOS allows.
///
/// On iOS 26 and later a running queue is a continued processing task
/// (`BGContinuedProcessingTask`). The app goes on running in the background
/// with network access, and the system shows the task as a Live Activity,
/// on the Lock Screen and in the Dynamic Island, with the title, subtitle
/// and progress given here and a stop button. The system may also end the
/// task itself. Either way it expires, and the queue is paused (`action`
/// with `pause`) so that it stops where the user can resume it. iOS has no
/// way to show a paused queue, so a paused one ends the task.
///
/// Older iOS, and a task the system refuses, get the time iOS gives any app
/// that leaves the screen (`beginBackgroundTask`, about half a minute):
/// enough for a photo on its way, after which iOS suspends the app.
///
/// The task does no work itself: the Dart side runs the downloads and says
/// what to show. Everything here runs on the main thread.
final class BackgroundDownloadsPlugin: NSObject, FlutterPlugin {
  private struct Status {
    let title: String
    let subtitle: String
    let fraction: Double
  }

  private static let progressSteps: Int64 = 1000

  private let channel: FlutterMethodChannel

  /// One task at a time, so one name: iOS wants it to begin with the app's
  /// identifier and to be listed in `BGTaskSchedulerPermittedIdentifiers`.
  private let taskIdentifier = "\(Bundle.main.bundleIdentifier ?? "io.jeph.grlab").downloads"

  /// What the running queue shows; nil while it is hidden or paused.
  private var status: Status?

  /// iOS kills an app that registers a task's handler twice.
  private var triedToRegister = false
  private var registered = false

  /// The task was asked for since the queue last stopped, so a refusal is
  /// not asked again with every status.
  private var submitted = false
  private var task: BGTask?
  private var grace: UIBackgroundTaskIdentifier = .invalid

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.jeph.grlab/downloads", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(BackgroundDownloadsPlugin(channel: channel), channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(
      self, selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let args = call.arguments as? [String: Any],
        let paused = args["paused"] as? Bool,
        let title = args["title"] as? String,
        let detail = args["detail"] as? String,
        let camera = args["camera"] as? String,
        let fraction = args["fraction"] as? Double
      else {
        result(FlutterError(
          code: "failed", message: "show needs paused, title, detail, camera and fraction",
          details: nil))
        return
      }
      if paused {
        end(finished: false)
        result(nil)
        return
      }
      let subtitle = [camera, detail].filter { !$0.isEmpty }.joined(separator: " · ")
      show(Status(title: title, subtitle: subtitle, fraction: fraction), result: result)
    case "hide":
      let args = call.arguments as? [String: Any]
      end(finished: args?["finished"] as? Bool ?? false)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func show(_ next: Status, result: @escaping FlutterResult) {
    status = next
    guard #available(iOS 26.0, *) else {
      result(nil)
      return
    }
    if let running = task as? BGContinuedProcessingTask {
      apply(next, to: running)
      result(nil)
      return
    }
    guard !submitted else {
      result(nil)
      return
    }
    submitted = true
    submit(next, result: result)
  }

  @available(iOS 26.0, *)
  private func submit(_ first: Status, result: @escaping FlutterResult) {
    if !triedToRegister {
      triedToRegister = true
      registered = BGTaskScheduler.shared.register(
        forTaskWithIdentifier: taskIdentifier, using: .main
      ) { [weak self] task in
        guard let self else {
          task.setTaskCompleted(success: false)
          return
        }
        self.began(task)
      }
    }
    guard registered else {
      result(FlutterError(
        code: "notStarted", message: "iOS did not accept the task \(taskIdentifier)",
        details: nil))
      return
    }
    let request = BGContinuedProcessingTaskRequest(
      identifier: taskIdentifier, title: first.title, subtitle: first.subtitle)
    // A queue behind other apps' tasks would start once this one's
    // downloads may be over; without the task they run as before.
    request.strategy = .fail
    if #available(iOS 27.0, *) {
      BGTaskScheduler.shared.submitTaskRequest(request) { error in
        DispatchQueue.main.async { result(error.map(Self.notStarted)) }
      }
      return
    }
    do {
      try BGTaskScheduler.shared.submit(request)
      result(nil)
    } catch {
      result(Self.notStarted(error))
    }
  }

  private static func notStarted(_ error: Error) -> FlutterError {
    let error = error as NSError
    return FlutterError(
      code: "notStarted",
      message: "iOS did not start the download task: \(error.domain) \(error.code)",
      details: nil)
  }

  /// The system started the task that `submit` asked for.
  private func began(_ started: BGTask) {
    guard #available(iOS 26.0, *), let continued = started as? BGContinuedProcessingTask,
      let status
    else {
      // The queue stopped before the system got to it.
      started.setTaskCompleted(success: false)
      return
    }
    task = continued
    continued.progress.totalUnitCount = Self.progressSteps
    continued.expirationHandler = { [weak self] in
      DispatchQueue.main.async { self?.expired(continued) }
    }
    apply(status, to: continued)
    endGrace()
  }

  @available(iOS 26.0, *)
  private func apply(_ shown: Status, to running: BGContinuedProcessingTask) {
    running.updateTitle(shown.title, subtitle: shown.subtitle)
    running.progress.completedUnitCount = Int64(
      (shown.fraction * Double(Self.progressSteps)).rounded())
  }

  /// The user pressed stop in the Live Activity, or the system took the
  /// task's time away.
  private func expired(_ ended: BGTask) {
    guard task === ended else { return }
    task = nil
    status = nil
    channel.invokeMethod("action", arguments: "pause")
    ended.setTaskCompleted(success: false)
  }

  /// The queue stopped: `finished` when nothing is left and nothing failed.
  private func end(finished: Bool) {
    status = nil
    submitted = false
    endGrace()
    if let running = task {
      task = nil
      running.setTaskCompleted(success: finished)
    } else if registered {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }
  }

  @objc private func didEnterBackground() {
    guard status != nil, task == nil, grace == .invalid else { return }
    grace = UIApplication.shared.beginBackgroundTask(withName: "GR Lab downloads") { [weak self] in
      self?.endGrace()
    }
  }

  @objc private func willEnterForeground() {
    endGrace()
  }

  private func endGrace() {
    guard grace != .invalid else { return }
    UIApplication.shared.endBackgroundTask(grace)
    grace = .invalid
  }
}
