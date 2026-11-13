import Flutter
import UIKit

/// `io.jeph.grphoto/window`: what a foldable iPhone (iPhone Duo, iOS 27.1)
/// says about the Flutter view that Flutter does not pass on yet: the edge
/// iOS puts its vertical bar on, the band the display folds along and
/// whether it is folded part of the way, and what the system draws over
/// the view. The Dart side (`PlatformWindowPose`) reads it with `get` and
/// is told of every change with `changed`.
///
/// The pose is a dictionary: `bar` (`left` or `right`, absent without a
/// vertical bar edge), `fold` and each of `occlusions` as
/// `[x, y, width, height]` in the view's points, `foldActive`, and
/// `hinge` (`closed`, `partiallyOpen`, `fullyOpen` or `unknown`) for the
/// debug log. It is empty before iOS 27.1.
final class WindowPosePlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private weak var observer: UIView?
  private var hinge = "unknown"
  private var sent: NSDictionary?

  private init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.jeph.grphoto/window", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(
      WindowPosePlugin(channel: channel, registrar: registrar), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "get" else {
      result(FlutterMethodNotImplemented)
      return
    }
    // Flutter delivers method calls on the main thread.
    MainActor.assumeIsolated {
      observe()
      let pose = self.pose()
      sent = pose as NSDictionary
      result(pose)
    }
  }

  /// Watches the Flutter view from now on. The view exists by the time the
  /// Dart side asks; until it is in a window its pose is empty, and the
  /// first layout there reports the real one.
  @MainActor private func observe() {
    guard #available(iOS 27.1, *), observer == nil,
      let view = registrar?.viewController?.view
    else { return }
    // A view of the Flutter view's size, which is laid out again whenever
    // that changes: unfolding, turning the phone, Split View.
    let watcher = LayoutWatcher(frame: view.bounds)
    watcher.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    watcher.isUserInteractionEnabled = false
    watcher.backgroundColor = .clear
    watcher.onLayout = { [weak self] in self?.report() }
    watcher.registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
      (watcher: LayoutWatcher, _: UITraitCollection) in watcher.onLayout?()
    }
    view.addSubview(watcher)
    observer = watcher
    view.addInteraction(
      UIHingeInteraction { [weak self] _, update in
        let status = update.hinge?.status
        MainActor.assumeIsolated {
          guard let self else { return }
          self.hinge =
            switch status {
            case .closed: "closed"
            case .partiallyOpen: "partiallyOpen"
            case .fullyOpen: "fullyOpen"
            default: "unknown"
            }
          self.report()
        }
      })
  }

  @MainActor private func report() {
    let pose = self.pose() as NSDictionary
    guard pose != sent else { return }
    sent = pose
    channel.invokeMethod("changed", arguments: pose)
  }

  @MainActor private func pose() -> [String: Any] {
    guard #available(iOS 27.1, *), let view = observer else { return [:] }
    var pose: [String: Any] = ["hinge": hinge]
    let rightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
    switch view.traitCollection.verticalBarEdge {
    case .leading: pose["bar"] = rightToLeft ? "right" : "left"
    case .trailing: pose["bar"] = rightToLeft ? "left" : "right"
    default: break
    }
    if let fold = view.reservedRegions(kind: .division, options: .includeInactive).first {
      pose["fold"] = Self.rect(fold.frame)
      pose["foldActive"] = fold.isActive
    }
    pose["occlusions"] = view.reservedRegions(kind: .occlusion).map { Self.rect($0.frame) }
    return pose
  }

  private static func rect(_ rect: CGRect) -> [Double] {
    [rect.minX, rect.minY, rect.width, rect.height].map { Double($0) }
  }
}

/// Calls [onLayout] whenever its size or safe area changes.
private final class LayoutWatcher: UIView {
  var onLayout: (@MainActor () -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    onLayout?()
  }
}
