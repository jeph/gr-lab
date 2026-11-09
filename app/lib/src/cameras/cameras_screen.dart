import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/cameras/camera_details.dart';
import 'package:grlab/src/cameras/camera_identity.dart';
import 'package:grlab/src/cameras/camera_presence.dart';
import 'package:grlab/src/cameras/recent_thumbs.dart';
import 'package:grlab/src/connection/connect_failure_view.dart';
import 'package:grlab/src/connection/connect_steps.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/library/image_orientation.dart';
import 'package:grlab/src/pairing/pairing_flow.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/settings/settings_screen.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// Where the app opens and where it returns whenever no camera is
/// connected (mock `b-home` … `b-home-lost`, and `b-welcome` before any
/// camera is paired). The camera used last is on a card with thumbnails
/// from its last visit; the others are listed below it. While the screen
/// is in front it scans, so each camera says whether it is nearby and
/// switched on. One camera is connected at a time.
class CamerasScreen extends StatefulWidget {
  const new({super.key, this.autoConnect = false});

  /// Connect to the camera used last as soon as the scan sees it nearby
  /// (once, when the app opens).
  final bool autoConnect;

  @override
  State<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends State<CamerasScreen> with RouteAware {
  late final AppModels _models = AppScope.of(context);
  late final CameraPresence _presence = CameraPresence(_models.services.camera);
  ModalRoute<void>? _route;

  /// Another route (pairing, details, settings) is on top.
  bool _covered = false;

  /// The app is visible: `inactive` still draws it (a system sheet over
  /// it), so only hiding it stops the scan.
  bool _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
  late final AppLifecycleListener _lifecycle;
  bool? _permission;
  bool _autoConnected = false;

  static bool _isVisible(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void initState() {
    super.initState();
    _models.cameras.addListener(_update);
    _models.connection.addListener(_update);
    _presence.addListener(_onPresence);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final visible = _isVisible(state);
        if (visible == _visible) return;
        _visible = visible;
        _update();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route && route is ModalRoute<void>) {
      if (_route != null) _models.routes.unsubscribe(this);
      _route = route;
      _models.routes.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _models.routes.unsubscribe(this);
    _models.cameras.removeListener(_update);
    _models.connection.removeListener(_update);
    _presence
      ..removeListener(_onPresence)
      ..dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    _covered = true;
    _update();
  }

  @override
  void didPopNext() {
    _covered = false;
    _update();
  }

  /// Scans while the screen is in front and the app visible, a camera is
  /// paired and no connection attempt needs Bluetooth for itself.
  void _update() {
    if (!mounted) return;
    final want =
        _visible &&
        !_covered &&
        _models.cameras.cameras.isNotEmpty &&
        _models.connection.status != ConnectionStatus.connecting;
    if (!want) {
      if (_presence.scanning) unawaited(_presence.stop());
      return;
    }
    switch (_permission) {
      case null:
        _permission = false;
        unawaited(_askPermission());
      case true when !_presence.scanning:
        _presence.start();
      case _:
        break;
    }
  }

  Future<void> _askPermission() async {
    final granted = await _models.services.camera.requestBluetoothPermission();
    if (!mounted) return;
    _permission = granted;
    _update();
  }

  void _onPresence() {
    final current = _models.cameras.current;
    if (widget.autoConnect &&
        !_autoConnected &&
        !_covered &&
        current != null &&
        _models.connection.status == ConnectionStatus.offline &&
        _presence.of(current) != Presence.away) {
      _autoConnected = true;
      unawaited(_connect(current.serial));
    }
  }

  /// Stops this screen's scan before the connection starts its own.
  Future<void> _connect(String serial) async {
    await _presence.stop();
    await _models.connection.connectTo(serial);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _models.cameras,
      _models.connection,
      _presence,
    ]),
    builder: (context, _) {
      final cameras = _models.cameras.cameras;
      return Scaffold(
        body: cameras.isEmpty
            ? const _Welcome()
            : _CameraList(
                cameras: cameras,
                presence: _presence,
                connection: _models.connection,
                onConnect: (serial) => unawaited(_connect(serial)),
              ),
      );
    },
  );
}

// -------------------------------------------------------------- welcome

/// The Cameras screen before any camera is paired (mock `b-welcome`).
class _Welcome extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final photo = constraints.maxHeight * .56;
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: photo,
              child: Image.asset(
                'assets/welcome.jpg',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            Positioned(
              top: photo * .53,
              left: 0,
              right: 0,
              height: photo * .47 + 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.bg.withValues(alpha: 0), c.bg],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              key: const Key('cameras-welcome'),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(28, photo * .5, 28, 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.l10n.camerasWelcomeWordmark,
                          style: GrFonts.monoStyle(context)
                              .copyWith(letterSpacing: 1.7),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.l10n.camerasWelcomeTitle,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.8,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.camerasWelcomeBody,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: c.t2,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ModelChip(context.l10n.camerasWelcomeModelGr3),
                            _ModelChip(context.l10n.camerasWelcomeModelGr3x),
                            _ModelChip(context.l10n.camerasWelcomeModelGr4),
                          ],
                        ),
                        const SizedBox(height: 26),
                        FilledButton.icon(
                          key: const Key('cameras-add'),
                          onPressed: () => unawaited(PairingFlow.push(context)),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: Text(context.l10n.camerasAddCamera),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.camerasWelcomeHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: c.t3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ModelChip extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(label, style: TextStyle(fontSize: 13, color: c.t2)),
      ),
    );
  }
}

// ----------------------------------------------------------------- list

class _CameraList extends StatelessWidget {
  const new({
    required this.cameras,
    required this.presence,
    required this.connection,
    required this.onConnect,
  });

  final List<SavedCamera> cameras;
  final CameraPresence presence;
  final ConnectionController connection;
  final ValueChanged<String> onConnect;

  @override
  Widget build(BuildContext context) {
    final current = cameras.first;
    final others = cameras.skip(1).toList();
    final connecting = connection.status == ConnectionStatus.connecting;
    // Bluetooth failures end the link; Wi-Fi ones are kept next to it.
    final failure = switch (connection.status) {
      ConnectionStatus.failed ||
      ConnectionStatus.bluetooth => connection.failure,
      _ => null,
    };
    final lost =
        failure != null &&
        failure.lost &&
        (failure.kind == ConnectFailureKind.wifi ||
            failure.kind == ConnectFailureKind.unreachable);
    final idleFor = connection.status == ConnectionStatus.bluetooth
        ? connection.idleClosedAfter
        : null;
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const Key('cameras'),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GrIconButton(
                  key: const Key('cameras-settings'),
                  icon: Icons.settings_outlined,
                  tooltip: context.l10n.camerasSettings,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text(
              context.l10n.camerasTitle,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
              ),
            ),
          ),
          if (lost)
            _Banner(
              key: const Key('cameras-lost'),
              icon: failure.kind == ConnectFailureKind.wifi
                  ? Icons.wifi_off_rounded
                  : Icons.bluetooth_disabled_rounded,
              title: context.l10n.camerasLostTitle(current.name),
              body: failure.kind == ConnectFailureKind.wifi
                  ? context.l10n.camerasLostWifiBody
                  : context.l10n.camerasLostBluetoothBody,
            )
          else if (idleFor != null)
            _Banner(
              key: const Key('cameras-idle'),
              icon: Icons.timer_outlined,
              title: context.l10n.camerasIdleTitle(current.name),
              body: context.l10n.camerasIdleBody(idleFor.inMinutes),
            ),
          _CameraCard(
            camera: current,
            presence: presence,
            connection: connection,
            // The banner says what happened; the card offers Connect.
            failure: lost ? null : failure,
            onConnect: () => onConnect(current.serial),
          ),
          SectionLabel(context.l10n.camerasOtherCameras),
          IgnorePointer(
            ignoring: connecting,
            child: AnimatedOpacity(
              opacity: connecting ? .42 : 1,
              duration: const Duration(milliseconds: 200),
              child: GroupBox(
                key: const Key('cameras-others'),
                children: [
                  for (final camera in others)
                    _OtherCameraRow(
                      camera: camera,
                      presence: presence,
                      onConnect: () => onConnect(camera.serial),
                    ),
                  const _AddCameraRow(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- card

/// The camera used last (mock `.ccard`): thumbnails, the link, buttons
/// to the camera's Library and Shoot pages, and Connect while it is not
/// linked; or the steps while connecting, or why the last attempt failed.
class _CameraCard extends StatelessWidget {
  const new({
    required this.camera,
    required this.presence,
    required this.connection,
    required this.failure,
    required this.onConnect,
  });

  final SavedCamera camera;
  final CameraPresence presence;
  final ConnectionController connection;
  final ConnectFailure? failure;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final status = connection.status;
    final connecting = status == ConnectionStatus.connecting;
    final linked = status == ConnectionStatus.bluetooth;
    final failure = this.failure;
    return Container(
      key: const Key('camera-card'),
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(GrRadii.lg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: c.s3,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.photo_camera_outlined, size: 24, color: c.t1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      camera.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      camera.identityLine(context.l10n, firmware: false),
                      style: GrFonts.monoStyle(context, size: 11.5),
                    ),
                  ],
                ),
              ),
              GrIconButton(
                key: const Key('camera-card-more'),
                icon: Icons.more_horiz_rounded,
                tooltip: context.l10n.camerasDetailsTooltip,
                size: 32,
                onPressed: () =>
                    unawaited(CameraDetailsScreen.push(context, camera.serial)),
              ),
            ],
          ),
          if (connecting) ...[
            Padding(
              key: const Key('camera-card-connecting'),
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: ConnectSteps(connection: connection),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              key: const Key('camera-card-cancel'),
              style: smallOutlinedStyle,
              // Cancelling the join keeps Bluetooth; cancelling the link
              // ends the attempt.
              onPressed: () => unawaited(
                connection.step == ConnectStep.wifi
                    ? connection.closeCamera()
                    : connection.disconnect(),
              ),
              child: Text(context.l10n.camerasCancel),
            ),
          ] else if (failure != null)
            ConnectFailureView(
              camera: camera,
              failure: failure,
              connection: connection,
            )
          else ...[
            _Thumbs(serial: camera.serial),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: linked
                      ? const _LinkedLabel()
                      : _NearLabel(
                          presence: presence,
                          camera: camera,
                          withModel: false,
                        ),
                ),
                const SizedBox(width: 10),
                GrIconButton(
                  key: const Key('camera-card-library'),
                  icon: Icons.grid_view_rounded,
                  tooltip: context.l10n.camerasLibrary,
                  size: 34,
                  onPressed: () =>
                      unawaited(connection.openCamera(CameraTab.library)),
                ),
                const SizedBox(width: 8),
                GrIconButton(
                  key: const Key('camera-card-shoot'),
                  icon: Icons.camera_outlined,
                  tooltip: context.l10n.camerasShoot,
                  size: 34,
                  onPressed: () =>
                      unawaited(connection.openCamera(CameraTab.shoot)),
                ),
                if (!linked) ...[
                  const SizedBox(width: 10),
                  FilledButton(
                    key: const Key('camera-card-connect'),
                    style: smallFilledStyle,
                    onPressed: onConnect,
                    child: Text(context.l10n.camerasConnect),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The card's link line while connected over Bluetooth.
class _LinkedLabel extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Row(
      key: const Key('camera-card-linked'),
      children: [
        Icon(Icons.bluetooth_connected_rounded, size: 16, color: c.ok),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            context.l10n.camerasConnectedViaBluetooth,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: c.t2),
          ),
        ),
      ],
    );
  }
}

/// A note above the camera card: the camera's link was lost (mock
/// `b-home-lost`), or its Wi-Fi was left for lack of use. Shown once: the
/// next attempt clears it.
class _Banner extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent.withValues(alpha: .32)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 12.5, color: c.t2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thumbnails of the newest shots kept from the camera's last visit;
/// nothing until the Library has loaded some.
class _Thumbs extends StatefulWidget {
  const new({required this.serial});

  final String serial;

  @override
  State<_Thumbs> createState() => _ThumbsState();
}

class _ThumbsState extends State<_Thumbs> {
  late Future<List<RecentThumb>> _thumbs = _load();

  Future<List<RecentThumb>> _load() =>
      loadRecentThumbs(AppScope.of(context).services.cacheDir, widget.serial);

  @override
  void didUpdateWidget(_Thumbs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serial != widget.serial) _thumbs = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _thumbs,
    builder: (context, snapshot) {
      final thumbs = snapshot.data;
      if (thumbs == null || thumbs.isEmpty) return const SizedBox.shrink();
      final px = (MediaQuery.devicePixelRatioOf(context) * 96).round();
      return Padding(
        key: const Key('camera-card-thumbs'),
        padding: const EdgeInsets.only(top: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: i < thumbs.length
                        ? ExifOrientation(
                            orientation: thumbs[i].orientation,
                            child: Image.memory(
                              thumbs[i].bytes,
                              fit: BoxFit.cover,
                              cacheWidth: px,
                              gaplessPlayback: true,
                            ),
                          )
                        : ColoredBox(color: GrColors.of(context).s2),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

// ------------------------------------------------------------ other rows

/// `GR IIIx · not nearby` with the presence dot (mock `.near`).
class _NearLabel extends StatelessWidget {
  const new({
    required this.presence,
    required this.camera,
    required this.withModel,
  });

  final CameraPresence presence;
  final SavedCamera camera;

  /// Rows say the model; the card already shows it.
  final bool withModel;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final p = presence.of(camera);
    final seen = switch (p) {
      Presence.nearbyOff => _Seen.nearbyOff,
      Presence.nearbyOn => _Seen.nearbyOn,
      Presence.nearby => _Seen.nearby,
      Presence.away when presence.settled => _Seen.away,
      Presence.away when presence.scanning => _Seen.looking,
      // Not scanning (no Bluetooth permission, Bluetooth off): unknown.
      Presence.away => null,
    };
    final model = withModel ? camera.model() : null;
    final text = switch ((model, seen)) {
      (null, null) => '',
      (final model?, null) => model,
      (null, final seen?) => seen.text(context.l10n),
      (final model?, final seen?) => seen.withModel(context.l10n, model),
    };
    final dot = switch (p) {
      Presence.nearbyOff => BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.ok, width: 1.5),
      ),
      Presence.nearbyOn ||
      Presence.nearby => BoxDecoration(shape: BoxShape.circle, color: c.ok),
      Presence.away => BoxDecoration(shape: BoxShape.circle, color: c.t3),
    };
    return Row(
      key: Key('camera-near-${camera.serial}'),
      children: [
        if (seen != null) ...[
          Container(width: 7, height: 7, decoration: dot),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: withModel ? 12 : 12.5, color: c.t2),
          ),
        ),
      ],
    );
  }
}

/// What the scan says about a camera, as [_NearLabel] words it.
enum _Seen {
  nearbyOff,
  nearbyOn,
  nearby,
  away,
  looking;

  String text(AppLocalizations l10n) => switch (this) {
    nearbyOff => l10n.camerasPresenceNearbyOff,
    nearbyOn => l10n.camerasPresenceNearbyOn,
    nearby => l10n.camerasPresenceNearby,
    away => l10n.camerasPresenceAway,
    looking => l10n.camerasPresenceLooking,
  };

  String withModel(AppLocalizations l10n, String model) => switch (this) {
    nearbyOff => l10n.camerasPresenceWithModelNearbyOff(model),
    nearbyOn => l10n.camerasPresenceWithModelNearbyOn(model),
    nearby => l10n.camerasPresenceWithModelNearby(model),
    away => l10n.camerasPresenceWithModelAway(model),
    looking => l10n.camerasPresenceWithModelLooking(model),
  };
}

class _OtherCameraRow extends StatelessWidget {
  const new({
    required this.camera,
    required this.presence,
    required this.onConnect,
  });

  final SavedCamera camera;
  final CameraPresence presence;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return InkWell(
      key: Key('camera-row-${camera.serial}'),
      onTap: () => unawaited(CameraDetailsScreen.push(context, camera.serial)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.s3,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.photo_camera_outlined, size: 18, color: c.t1),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    camera.name,
                    style: TextStyle(fontSize: 15, color: c.t1),
                  ),
                  const SizedBox(height: 3),
                  _NearLabel(
                    presence: presence,
                    camera: camera,
                    withModel: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: Key('camera-row-connect-${camera.serial}'),
              style: smallOutlinedStyle,
              onPressed: onConnect,
              child: Text(context.l10n.camerasConnect),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCameraRow extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return InkWell(
      key: const Key('cameras-add'),
      onTap: () => unawaited(PairingFlow.push(context)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.s3,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.add_rounded, size: 18, color: c.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  context.l10n.camerasAddCamera,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
