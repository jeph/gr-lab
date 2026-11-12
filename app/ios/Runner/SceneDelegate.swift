import Flutter
import UIKit

/// Shows the app's one Flutter engine ([AppDelegate.runningEngine]) in the
/// scene's window. The window is built here rather than from a storyboard,
/// whose view controller would start an engine of its own: when iOS started
/// GR Photo in the background for a camera that was switched on, the Dart
/// side already runs, and the screen has to show that one.
class SceneDelegate: UIResponder, UIWindowSceneDelegate, FlutterSceneLifeCycleProvider {
  var sceneLifeCycleDelegate = FlutterPluginSceneLifeCycleDelegate()

  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let windowScene = scene as? UIWindowScene,
      let app = UIApplication.shared.delegate as? AppDelegate
    {
      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = FlutterViewController(
        engine: app.runningEngine(), nibName: nil, bundle: nil)
      self.window = window
      window.makeKeyAndVisible()
    }
    // After the window: Flutter finds the engine the scene's events go to
    // through its root view controller.
    sceneLifeCycleDelegate.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneDidDisconnect(scene)
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneWillEnterForeground(scene)
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneDidBecomeActive(scene)
  }

  func sceneWillResignActive(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneWillResignActive(scene)
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneDidEnterBackground(scene)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    sceneLifeCycleDelegate.scene(scene, openURLContexts: URLContexts)
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    sceneLifeCycleDelegate.scene(scene, continue: userActivity)
  }

  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    sceneLifeCycleDelegate.windowScene(
      windowScene, performActionFor: shortcutItem, completionHandler: completionHandler)
  }
}
