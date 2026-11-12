import UIKit

/// The camera layer's native code that has to run when iOS starts GR Photo
/// in the background, before any Flutter engine exists or without one: for
/// a significant location change or a visit (the location history).
public enum GrCameraBackground {
  /// The background modes the app declares in its `Info.plist`.
  static let declaredModes = Set(
    Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? [])

  private static var unlockObserver: NSObjectProtocol?

  /// Call from the app delegate's
  /// `application(_:didFinishLaunchingWithOptions:)`, on the main thread.
  /// Creates the location manager of the history if the history was on
  /// when the app last ran, so iOS can deliver the events it launched the
  /// app for. Nothing is created, and so nothing is asked of the user, when
  /// it was off.
  public static func applicationDidFinishLaunching() {
    PhoneLocator.resumeIfInUse()
    guard unlockObserver == nil else { return }
    // Between a restart of the phone and its first unlock the saved state
    // cannot be read, so it looks as if the history was off.
    unlockObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil,
      queue: .main
    ) { _ in PhoneLocator.resumeIfInUse() }
  }
}
