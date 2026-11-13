/// What iOS shows while a run is held (`holdRun`): the texts are the app's,
/// already in the user's language.
public struct GrCameraRunNotice: Equatable {
  /// Names the run to the app, which chooses it; never shown. The presenter
  /// hands it back with a Stop ([GrCameraRun.stopPressed]).
  public let run: String

  /// First line: the camera the location goes to.
  public let title: String

  /// Second line: what is happening now.
  public let text: String

  /// Label of the button that turns live geotagging off.
  public let stopLabel: String
}

/// Shows the notice of a held run. The app implements it with a Live
/// Activity: a Live Activity is drawn by a widget extension, which is the
/// app's to build, so the camera layer only says what to show and when.
/// Called on the main queue.
public protocol GrCameraRunNoticePresenter: AnyObject {
  /// Shows `notice`, or replaces the one shown. Called again with the same
  /// notice when GR Photo comes back on screen, for a presenter that could
  /// not show it while the app was off screen.
  func show(_ notice: GrCameraRunNotice)

  /// Takes the notice away; nothing happens when none is shown.
  func remove()
}

/// The app's side of a held run on iOS. Main queue only.
public enum GrCameraRun {
  /// Set by the app when it starts, before a Flutter engine can hold a run.
  /// Without one a run shows no notice.
  public static var noticePresenter: GrCameraRunNoticePresenter?

  /// The user pressed Stop on a notice of the run `run`. For the run held
  /// now, Dart turns live geotagging off and then releases it
  /// (`runStopped`). A notice can also outlive its run (a Live Activity
  /// stays up when iOS ends the app while it is suspended): its Stop is kept
  /// until Dart takes it (`takeRunStop`).
  public static func stopPressed(run: String) {
    PhoneLocator.shared.runStoppedByUser(run)
  }

  /// A line for the debug log from the app's presenter, under the rule of
  /// the location channel's own lines ([DartLink]).
  public static func log(_ message: String) {
    PhoneLocator.shared.dart.log(message)
  }
}
