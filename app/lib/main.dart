import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:grphoto/src/app.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/debug/debug_log.dart';
import 'package:grphoto/src/demo/demo_services.dart';
import 'package:grphoto/src/platform/device_services.dart';
import 'package:grphoto/src/settings/bundled_licenses.dart';

/// `--dart-define=GR_DEMO=true` runs against the simulated camera, for the
/// emulator and for trying the app without a GR.
const _demo = bool.fromEnvironment('GR_DEMO');

/// Everything runs inside [runWithDebugLog], so what the app prints lands in
/// the debug log once it is open (Settings, "Enable debug logging").
///
/// Android also runs this with no screen, when a camera with live
/// geotagging is switched on while GR Photo is not running. Nothing here
/// waits for one: the models start everything that has to run then
/// (`GeotagController.start`), and the widgets are simply not shown until
/// the user opens the app, which finds them as this left them.
Future<void> main() async {
  DebugLog? log;
  await runWithDebugLog(() => log, () async {
    WidgetsFlutterBinding.ensureInitialized();
    LicenseRegistry.addLicense(bundledLicenses);
    final services = _demo
        ? await buildDemoServices()
        : await buildDeviceServices();
    final models = await AppModels.load(services);
    log = models.debugLog;
    PlatformDispatcher.instance.onError = models.debugLog.onUncaughtError;
    runApp(GrPhotoApp(models: models));
  });
}
