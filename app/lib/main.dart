import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:grlab/src/app.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/debug/debug_log.dart';
import 'package:grlab/src/demo/demo_services.dart';
import 'package:grlab/src/platform/device_services.dart';

/// `--dart-define=GR_DEMO=true` runs against the simulated camera, for the
/// emulator and for trying the app without a GR.
const _demo = bool.fromEnvironment('GR_DEMO');

/// Everything runs inside [runWithDebugLog], so what the app prints lands in
/// the debug log once it is open (Settings, "Enable debug logging").
Future<void> main() async {
  DebugLog? log;
  await runWithDebugLog(() => log, () async {
    WidgetsFlutterBinding.ensureInitialized();
    LicenseRegistry.addLicense(_fontLicenses);
    final services = _demo
        ? await buildDemoServices()
        : await buildDeviceServices();
    final models = await AppModels.load(services);
    log = models.debugLog;
    PlatformDispatcher.instance.onError = models.debugLog.onUncaughtError;
    runApp(GrLabApp(models: models));
  });
}

Stream<LicenseEntry> _fontLicenses() async* {
  for (final (package, file) in [
    ('Inter', 'Inter-OFL.txt'),
    ('JetBrains Mono', 'JetBrainsMono-OFL.txt'),
  ]) {
    yield LicenseEntryWithLineBreaks([
      package,
    ], await rootBundle.loadString('assets/fonts/$file'));
  }
}
