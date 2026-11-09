import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppDataFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Keeps everything GR Lab stores (Application Support: settings, paired
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
      NSLog("GR Lab: could not exclude app data from backup: \(error)")
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "GrLabMediaPlugin") {
      MediaPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "GrLabDevicePlugin") {
      // The name the camera shows under Paired Devices. Since iOS 16 this
      // is the model ("iPhone") unless the app holds a special entitlement.
      FlutterMethodChannel(name: "io.jeph.grlab/device", binaryMessenger: registrar.messenger())
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
