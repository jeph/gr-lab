import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
