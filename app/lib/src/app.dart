import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'cameras/cameras_screen.dart';
import 'connection/connection_controller.dart';
import 'connection/wifi_consent_dialog.dart';
import 'library/library_screen.dart';
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
        navigatorObservers: [models.routes],
        home: const RootScreen(),
      ),
    ),
  );
}

/// The Library while a camera is connected or quietly reconnecting, the
/// Cameras screen otherwise; leaving a session returns there, closing
/// whatever was open over the Library. Also tells the connection whether
/// the app is in front, and asks before the first join of a camera's
/// Wi-Fi when the platform needs it.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final AppModels _models = AppScope.of(context);
  late final AppLifecycleListener _lifecycle;
  bool _inSession = false;

  /// The Cameras screen connects to the camera used last when it sees it
  /// nearby, only until the first connection attempt of this launch,
  /// whoever starts it (that screen, pairing, or the user).
  bool _autoConnect = true;
  WifiConsentRequest? _shownConsent;

  /// The route showing [_shownConsent], while it is open.
  DialogRoute<bool>? _consentRoute;

  @override
  void initState() {
    super.initState();
    _inSession = _models.connection.inSession;
    _models.connection.addListener(_onConnection);
    // `inactive` covers system sheets drawn over the app, including
    // Android's own Wi-Fi approval screen; only leaving the app counts.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _models.connection.foreground =
          state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _onConnection());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _models.connection.removeListener(_onConnection);
    super.dispose();
  }

  void _onConnection() {
    final inSession = _models.connection.inSession;
    if (_models.connection.status != ConnectionStatus.offline) {
      _autoConnect = false;
    }
    if (_inSession && !inSession) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _inSession = inSession;
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
    listenable: Listenable.merge([_models.cameras, _models.connection]),
    builder: (context, _) =>
        _models.cameras.current != null && _models.connection.inSession
        ? const LibraryScreen()
        : CamerasScreen(autoConnect: _autoConnect),
  );
}
