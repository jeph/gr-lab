import 'package:flutter/widgets.dart';

import 'connection/connection_controller.dart';
import 'data/cameras.dart';
import 'data/settings.dart';
import 'services.dart';

/// App-wide models, created once in `main` and reached through
/// [AppScope.of]. Widgets listen to the individual notifiers.
final class AppModels {
  AppModels({
    required this.services,
    required this.settings,
    required this.cameras,
    required this.connection,
  });

  static Future<AppModels> load(AppServices services) async {
    final settings = await SettingsController.load(services.dataDir);
    final cameras = await CameraStore.load(services.dataDir);
    return AppModels(
      services: services,
      settings: settings,
      cameras: cameras,
      connection: ConnectionController(
        services: services,
        cameras: cameras,
        settings: settings,
      ),
    );
  }

  final AppServices services;
  final SettingsController settings;
  final CameraStore cameras;
  final ConnectionController connection;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.models, required super.child});

  final AppModels models;

  static AppModels of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.models;

  @override
  bool updateShouldNotify(AppScope oldWidget) => models != oldWidget.models;
}
