import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_scope.dart';
import 'src/demo/demo_services.dart';
import 'src/platform/device_services.dart';

/// `--dart-define=GR_DEMO=true` runs against the simulated camera, for the
/// emulator and for trying the app without a GR.
const _demo = bool.fromEnvironment('GR_DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(_fontLicenses);
  final services = _demo
      ? await buildDemoServices()
      : await buildDeviceServices();
  final models = await AppModels.load(services);
  runApp(GrLabApp(models: models));
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
