import Flutter
import UIKit
import gr_camera

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// GR Photo's one Flutter engine, once something needs the Dart side.
  private var engine: FlutterEngine?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppDataFromBackup()
    // iOS also starts GR Photo in the background, with no scene and so no
    // screen: for a location event of the history, which native code
    // stores by itself, or for a camera its Bluetooth scan found switched
    // on, which the Dart side has to link and send the location to.
    GrCameraBackground.startDart = { [weak self] in _ = self?.runningEngine() }
    GrCameraBackground.applicationDidFinishLaunching()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The engine running the Dart side, started at the first call: by the
  /// scene for its screen ([SceneDelegate]), or before any scene by a
  /// camera seen switched on. The scene that connects later shows the
  /// engine that is already running, so the app is never started twice.
  func runningEngine() -> FlutterEngine {
    if let engine { return engine }
    let engine = FlutterEngine(name: "io.jeph.grphoto")
    engine.run()
    registerPlugins(engine)
    self.engine = engine
    return engine
  }

  /// Keeps everything GR Photo stores (Application Support: settings, paired
  /// cameras, downloads and the debug log, which holds the camera's Wi-Fi
  /// passphrase) out of iCloud and computer backups. The cache is never
  /// backed up. Android turns backup off with `android:allowBackup`.
  private func excludeAppDataFromBackup() {
    do {
      var url = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
    } catch {
      NSLog("GR Photo: could not exclude app data from backup: \(error)")
    }
  }

  private func registerPlugins(_ registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "GrPhotoMediaPlugin") {
      MediaPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "GrPhotoBackgroundDownloadsPlugin") {
      BackgroundDownloadsPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "GrPhotoDevicePlugin") {
      // The name the camera shows under Paired Devices. Since iOS 16 this
      // is the model ("iPhone") unless the app holds a special entitlement.
      FlutterMethodChannel(name: "io.jeph.grphoto/device", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          if call.method == "name" {
            result(UIDevice.current.name)
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }
}
