import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'connection/connection_controller.dart';
import 'connection/wifi_consent_dialog.dart';
import 'library/library_screen.dart';
import 'pairing/pairing_flow.dart';
import 'theme/tokens.dart';

class GrLabApp extends StatelessWidget {
  const GrLabApp({super.key, required this.models});

  final AppModels models;

  @override
  Widget build(BuildContext context) => AppScope(
    models: models,
    child: ListenableBuilder(
      listenable: models.settings,
      builder: (context, _) => MaterialApp(
        title: 'GR Lab',
        debugShowCheckedModeBanner: false,
        theme: grTheme(Brightness.light),
        darkTheme: grTheme(Brightness.dark),
        themeMode: models.settings.themeMode,
        home: const RootScreen(),
      ),
    ),
  );
}

/// Pairing until a camera is paired, then the Library. Connecting starts
/// automatically whenever a paired camera becomes current. Also tells the
/// connection whether the app is in front, and asks before the first join
/// of a camera's Wi-Fi when the platform needs it.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final AppModels _models = AppScope.of(context);
  late final AppLifecycleListener _lifecycle;
  String? _connectedSerial;
  WifiConsentRequest? _shownConsent;

  /// The route showing [_shownConsent], while it is open.
  DialogRoute<bool>? _consentRoute;

  @override
  void initState() {
    super.initState();
    _models.cameras.addListener(_autoConnect);
    _models.connection.addListener(_onConnection);
    // `inactive` covers system sheets drawn over the app, including
    // Android's own Wi-Fi approval screen; only leaving the app counts.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _models.connection.foreground =
          state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
      _onConnection();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _models.connection.removeListener(_onConnection);
    _models.cameras.removeListener(_autoConnect);
    super.dispose();
  }

  void _autoConnect() {
    final serial = _models.cameras.current?.serial;
    if (serial == null || serial == _connectedSerial) return;
    _connectedSerial = serial;
    unawaited(_models.connection.connect());
  }

  void _onConnection() {
    final request = _models.connection.wifiConsent;
    if (identical(request, _shownConsent)) return;
    // Withdrawn or replaced: close that question only, and only while it
    // is still showing (an answered one is already on its way out).
    final open = _consentRoute;
    _consentRoute = null;
    if (open != null && open.isActive) open.navigator!.removeRoute(open);
    _shownConsent = request;
    if (request != null) unawaited(_askWifi(request));
  }

  Future<void> _askWifi(WifiConsentRequest request) async {
    final connection = _models.connection;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _consentRoute = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      // A stray tap beside it must not count as Not now.
      barrierDismissible: false,
      builder: (_) => WifiConsentDialog(request: request),
    );
    final join = await navigator.push(route);
    if (identical(_consentRoute, route)) _consentRoute = null;
    if (identical(connection.wifiConsent, request)) {
      connection.answerWifiConsent(join ?? false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _models.cameras,
    builder: (context, _) => _models.cameras.current == null
        ? const PairingFlow()
        : const LibraryScreen(),
  );
}
