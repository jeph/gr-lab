import ActivityKit
import UIKit
import gr_camera

/// Shows the notice of a held geotagging run (`GrCameraRunNotice`) as a Live
/// Activity, on the Lock Screen and in the Dynamic Island: what Android
/// shows as its geotagging notification. The LiveActivity extension draws
/// it (`GeotagActivityWidget`).
///
/// iOS starts a Live Activity only for an app that is on screen, so a run
/// held off screen (the camera came on after the run's hour of waiting was
/// over) shows none until GR Photo is next opened; the camera layer shows
/// the notice again then. It also lets the user swipe one away and ends one
/// after eight hours, with the run going on: either is started anew the next
/// time the notice changes or GR Photo is opened.
///
/// iOS 17 and later, the first with buttons in a Live Activity; earlier
/// versions show no notice. Main queue only.
@available(iOS 17.0, *)
final class GeotagLiveActivity: GrCameraRunNoticePresenter {
  /// How long the end of GR Photo waits for iOS to take the activity away.
  private static let terminationWait: TimeInterval = 2

  private static let shared = GeotagLiveActivity()

  private var activity: Activity<GeotagActivityAttributes>?
  private var shown: GeotagActivityAttributes.ContentState?

  /// The last of the updates and endings asked of iOS, which run one after
  /// the other so that the newest content is the one that stays.
  private var work: Task<Void, Never>?

  /// Call when the app has launched, before a Flutter engine holds a run.
  @MainActor static func install() {
    GrCameraRun.noticePresenter = shared
    StopGeotaggingIntent.onPerform = { GrCameraRun.stopPressed(run: $0) }
    shared.endLeftovers()
    // Without a queue the block runs where the notification is posted, on
    // the main queue, before the process ends.
    NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification, object: nil, queue: nil
    ) { _ in shared.willTerminate() }
  }

  func show(_ notice: GrCameraRunNotice) {
    let state = GeotagActivityAttributes.ContentState(
      title: notice.title, text: notice.text, stopLabel: notice.stopLabel)
    if let activity, activity.activityState == .active, activity.attributes.run == notice.run {
      guard state != shown else { return }
      shown = state
      enqueue { await activity.update(ActivityContent(state: state, staleDate: nil)) }
      GrCameraRun.log("Live Activity updated: \"\(state.title)\" / \"\(state.text)\"")
      return
    }
    // None yet, or the user swiped it away, or iOS ended it.
    remove()
    do {
      activity = try Activity.request(
        attributes: GeotagActivityAttributes(run: notice.run),
        content: ActivityContent(state: state, staleDate: nil))
      shown = state
      GrCameraRun.log("Live Activity started: \"\(state.title)\" / \"\(state.text)\"")
    } catch {
      // GR Photo is off screen, or the user turned Live Activities off for
      // it in the Settings app.
      GrCameraRun.log("Live Activity not started: \(error)")
    }
  }

  func remove() {
    guard let ended = activity else { return }
    activity = nil
    shown = nil
    enqueue { await ended.end(nil, dismissalPolicy: .immediate) }
  }

  /// Ends the activities an earlier process left behind: iOS ended GR Photo
  /// or it crashed while a run was held, and the run ended with it. A Stop
  /// pressed on such an activity starts GR Photo in the background, which
  /// takes it away here.
  private func endLeftovers() {
    let leftovers = Activity<GeotagActivityAttributes>.activities
    guard !leftovers.isEmpty else { return }
    enqueue {
      for leftover in leftovers {
        await leftover.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  /// GR Photo is being ended while it runs, as when it is swiped away in
  /// the app switcher: the run ends with it, so the activity must not stay.
  /// iOS takes it away asynchronously, and the process is gone once this
  /// returns, so this waits for it.
  private func willTerminate() {
    if activity != nil { GrCameraRun.log("Live Activity ended with GR Photo") }
    remove()
    guard let pending = work else { return }
    let done = DispatchSemaphore(value: 0)
    Task.detached {
      await pending.value
      done.signal()
    }
    _ = done.wait(timeout: .now() + Self.terminationWait)
  }

  private func enqueue(_ step: @escaping @Sendable () async -> Void) {
    let previous = work
    // Detached, so that it also runs while `willTerminate` holds the main
    // queue.
    work = Task.detached {
      await previous?.value
      await step()
    }
  }
}
