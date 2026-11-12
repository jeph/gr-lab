import UIKit

/// The camera layer's native code that has to run when iOS starts GR Photo
/// in the background, before any Flutter engine exists or without one: for
/// a significant location change or a visit (the location history), or for
/// a camera its Bluetooth scan found (the power-on watch).
public enum GrCameraBackground {
  /// The background modes the app declares in its `Info.plist`.
  static let declaredModes = Set(
    Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? [])

  private static var unlockObserver: NSObjectProtocol?

  /// Starts the app's Dart side when none runs; set by the app delegate
  /// before [applicationDidFinishLaunching]. The power-on watch calls it
  /// for a camera seen switched on while iOS runs GR Photo with no scene,
  /// and so with no Flutter engine: the Dart side links the camera and
  /// sends it the location. Location events of the history need no Dart.
  public static var startDart: (() -> Void)?

  /// Call from the app delegate's
  /// `application(_:didFinishLaunchingWithOptions:)`, on the main thread.
  /// Creates the location manager and the Bluetooth central manager that
  /// were in use when the app last ran, so iOS can deliver the events it
  /// launched the app for. Nothing is created, and so nothing is asked of
  /// the user, when neither was in use.
  public static func applicationDidFinishLaunching() {
    resume()
    guard unlockObserver == nil else { return }
    // Between a restart of the phone and its first unlock the saved state
    // cannot be read, so it looks as if nothing was in use.
    unlockObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil,
      queue: .main
    ) { _ in Self.resume() }
  }

  private static func resume() {
    PhoneLocator.resumeIfInUse()
    PowerOnWatcher.resumeIfInUse()
  }
}
