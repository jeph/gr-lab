import Flutter
import UIKit
import gr_camera

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppDataFromBackup()
    // iOS also starts GR Photo in the background, with no scene and so no
    // Flutter engine, for a location event of the history. Native code
    // stores it by itself.
    GrCameraBackground.applicationDidFinishLaunching()
    if #available(iOS 17.0, *) {
      GeotagLiveActivity.install()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "GrPhotoMediaPlugin") {
      MediaPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "GrPhotoBackgroundDownloadsPlugin") {
      BackgroundDownloadsPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "GrPhotoWindowPosePlugin") {
      WindowPosePlugin.register(with: registrar)
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
