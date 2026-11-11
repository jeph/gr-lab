import 'dart:async';

import 'package:flutter/material.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/camera/camera_pages.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/connection/idle_disconnect.dart';
import 'package:grlab/src/connection/wifi_consent_dialog.dart';
import 'package:grlab/src/downloads/download_background.dart';
import 'package:grlab/src/home/home_pages.dart';
import 'package:grlab/src/theme/tokens.dart';

class GrLabApp extends StatelessWidget {
  const new({required this.models, super.key});

  final AppModels models;

  @override
  Widget build(BuildContext context) => AppScope(
    models: models,
    child: ListenableBuilder(
      listenable: models.settings,
      builder: (context, _) {
        final chosen = models.settings.theme.colors;
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The language chosen in Settings, or else the phone's.
          locale: models.settings.language,
          localeListResolutionCallback: resolveAppLocale,
          debugShowCheckedModeBanner: false,
          // Without a dark theme, the app keeps the chosen one when the
          // phone is in dark mode.
          theme: grTheme(chosen ?? GrColors.light),
          darkTheme: chosen == null ? grTheme(GrColors.dark) : null,
          navigatorObservers: [models.routes, models.idle.observer],
          builder: (context, child) => IdleInput(
            idle: models.idle,
            child: DownloadBackground(child: child!),
          ),
          home: const RootScreen(),
        );
      },
    ),
  );
}

/// The home pages (the Cameras screen and the saved looks), with the
/// camera's pages (Library, Shoot and Looks) pushed over them while
/// [ConnectionController.tab] is set and the camera is linked. Going back
/// from them closes them ([ConnectionController.closeCamera]); the session
/// ending pops back to the home pages, closing whatever was open over
/// them. Also tells the connection whether the app is in front, and asks
/// before the first join of a camera's Wi-Fi when the platform needs it.
class RootScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final AppModels _models = AppScope.of(context);
  late final AppLifecycleListener _lifecycle;

  /// The Cameras screen connects to the camera used last when it sees it
  /// nearby (unless Settings says not to,
  /// `SettingsController.connectWhenNearby`), only until the first
  /// connection attempt of this launch, whoever starts it (that screen,
  /// pairing, or the user).
  bool _autoConnect = true;
  WifiConsentRequest? _shownConsent;

  /// The route showing [_shownConsent], while it is open.
  DialogRoute<bool>? _consentRoute;

  /// The camera's pages, while they are pushed.
  Route<void>? _cameraRoute;

  @override
  void initState() {
    super.initState();
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
    final connection = _models.connection;
    if (connection.status != ConnectionStatus.offline) {
      _autoConnect = false;
    }
    final pages =
        connection.tab != null &&
        _models.cameras.current != null &&
        switch (connection.status) {
          ConnectionStatus.connecting ||
          ConnectionStatus.bluetooth ||
          ConnectionStatus.connected => true,
          ConnectionStatus.offline || ConnectionStatus.failed => false,
        };
    if (pages && _cameraRoute == null) {
      _openCamera();
    } else if (!pages && _cameraRoute != null) {
      _cameraRoute = null;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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

  void _openCamera() {
    final route = _cameraRoute = MaterialPageRoute<void>(
      builder: (_) => const CameraPages(),
    );
    unawaited(
      Navigator.of(context).push(route).then((_) {
        if (!identical(_cameraRoute, route)) return;
        // Popped by the user (back), not by the session ending.
        _cameraRoute = null;
        unawaited(_models.connection.closeCamera());
      }),
    );
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
      connection.answerWifiConsent(join: join ?? false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_models.connection, _models.settings]),
    builder: (context, _) => HomePages(
      autoConnect: _autoConnect && _models.settings.connectWhenNearby,
    ),
  );
}
