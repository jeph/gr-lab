import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/camera/camera_tab_bar.dart';
import 'package:grlab/src/camera/camera_top_bar.dart';
import 'package:grlab/src/cameras/camera_details.dart';
import 'package:grlab/src/cameras/camera_drawing.dart';
import 'package:grlab/src/cameras/camera_identity.dart';
import 'package:grlab/src/cameras/camera_presence.dart';
import 'package:grlab/src/connection/connect_failure_view.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/pairing/pairing_flow.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/settings/settings_screen.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// Where the app opens and where it returns whenever no camera is
/// connected (mock `b-home` … `b-home-lost`, and `b-welcome` before any
/// camera is paired), on the home dock beside the saved looks. The camera
/// used last is on a card with a drawing of it, its link and power, and
/// its pages; the others are listed below it. While the screen is in front
/// it scans, so each camera says whether it is nearby and switched on. One
/// camera is connected at a time.
class CamerasScreen extends StatefulWidget {
  const new({super.key, this.autoConnect = false, this.shown = true});

  /// Connect to the camera used last as soon as the scan sees it nearby
  /// (once, when the app opens).
  final bool autoConnect;

  /// The home dock shows this screen rather than the saved looks. Hidden,
  /// it neither scans nor connects by itself.
  final bool shown;

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

  /// The Bluetooth permission's last answer; null until asked, and again
  /// once a denial may have changed in the system settings: when the app
  /// is hidden or another route covers the screen. Asked again when the
  /// screen is back in front.
  bool? _permission;
  bool _askingPermission = false;
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
        if (!visible) _forgetDenial();
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
    _forgetDenial();
    _update();
  }

  @override
  void didPopNext() {
    _covered = false;
    _update();
  }

  @override
  void didUpdateWidget(CamerasScreen old) {
    super.didUpdateWidget(old);
    if (widget.shown == old.shown) return;
    if (!widget.shown) _forgetDenial();
    _update();
  }

  /// Shown on the home dock, with no other route over it.
  bool get _inFront => widget.shown && !_covered;

  /// Scans while the screen is in front and the app visible, a camera is
  /// paired and no connection attempt needs Bluetooth for itself.
  void _update() {
    if (!mounted) return;
    final want =
        _visible &&
        _inFront &&
        _models.cameras.cameras.isNotEmpty &&
        _models.connection.status != ConnectionStatus.connecting;
    if (!want) {
      if (_presence.scanning) unawaited(_presence.stop());
      return;
    }
    switch (_permission) {
      case null when !_askingPermission:
        unawaited(_askPermission());
      case true when !_presence.scanning:
        _presence.start();
      case _:
        break;
    }
  }

  Future<void> _askPermission() async {
    _askingPermission = true;
    final granted = await _models.services.camera.requestBluetoothPermission();
    _askingPermission = false;
    if (!mounted) return;
    _permission = granted;
    _update();
  }

  /// The user may grant a denied permission in the system settings, or on
  /// another route (pairing), while this screen is not in front.
  void _forgetDenial() {
    if (_permission == false) _permission = null;
  }

  void _onPresence() {
    final current = _models.cameras.current;
    if (widget.autoConnect &&
        !_autoConnected &&
        _inFront &&
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
        // Above the home dock.
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          PageTitle(
            context.l10n.camerasTitle,
            actions: [
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
            // The banner says what happened.
            failure: lost ? null : failure,
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

/// The camera used last (mock `.ccard`): a drawing of its model
/// ([CameraDrawing]), an icon for each of its links, which pulses while
/// that link is being made, its power button and buttons to its pages
/// ([ConnectionController.tabs]); or Cancel while Bluetooth is linked for
/// a new connection, or why the last attempt failed.
class _CameraCard extends StatelessWidget {
  const new({
    required this.camera,
    required this.presence,
    required this.connection,
    required this.failure,
  });

  final SavedCamera camera;
  final CameraPresence presence;
  final ConnectionController connection;
  final ConnectFailure? failure;

  /// Whether the camera is on: from its session while there is one, else
  /// from its advertisement; null when neither says.
  bool? _cameraOn(Presence seen) => switch (connection.status) {
    ConnectionStatus.bluetooth ||
    ConnectionStatus.connected => !connection.cameraOff,
    _ => switch (seen) {
      Presence.nearbyOn => true,
      Presence.nearbyOff => false,
      Presence.nearby || Presence.away => null,
    },
  };

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final seen = presence.of(camera);
    final on = _cameraOn(seen);
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
              _BluetoothLink.of(connection, seen).icon(c, l10n),
              const SizedBox(width: 8),
              _WifiLink.of(connection).icon(c, l10n),
              const Spacer(),
              GrIconButton(
                key: const Key('camera-card-more'),
                icon: Icons.more_horiz_rounded,
                tooltip: context.l10n.camerasDetailsTooltip,
                onPressed: () =>
                    unawaited(CameraDetailsScreen.push(context, camera.serial)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: ExcludeSemantics(
                  child: CameraDrawing(
                    key: const Key('camera-card-drawing'),
                    body: camera.body,
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      camera.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4,
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
              const SizedBox(width: 12),
              _PowerButton(camera: camera, connection: connection, on: on),
            ],
          ),
          _CardFoot(child: _foot(context)),
        ],
      ),
    );
  }

  /// Cancel while Bluetooth is linked for a new connection, why the last
  /// attempt failed, or the buttons to the camera's pages; keyed by which,
  /// so [_CardFoot] brings each in.
  Widget _foot(BuildContext context) {
    final failure = this.failure;
    final l10n = context.l10n;
    final linking =
        connection.status == ConnectionStatus.connecting &&
        connection.step == ConnectStep.bluetooth;
    if (linking) {
      return Padding(
        key: const ValueKey('cancel'),
        padding: const EdgeInsets.only(top: 16),
        child: OutlinedButton(
          key: const Key('camera-card-cancel'),
          style: smallOutlinedStyle,
          onPressed: () => unawaited(connection.disconnect()),
          child: Text(l10n.camerasCancel),
        ),
      );
    }
    if (failure != null) {
      return ConnectFailureView(
        key: const ValueKey('failure'),
        camera: camera,
        failure: failure,
        connection: connection,
      );
    }
    return Padding(
      key: const ValueKey('pages'),
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          for (final (i, tab) in connection.tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _PageButton(
                key: Key('camera-card-${tab.name}'),
                icon: CameraTabBar.icon(tab),
                label: switch (tab) {
                  CameraTab.library => l10n.camerasLibrary,
                  CameraTab.shoot => l10n.camerasShoot,
                  CameraTab.looks => l10n.camerasLooks,
                },
                onPressed: () => unawaited(connection.openCamera(tab)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The foot of the camera card. When what it holds changes, as when the
/// buttons to the camera's pages follow the Bluetooth link, the new
/// content fades and slides in while the card grows or shrinks to fit it;
/// at once when the platform asks for less motion.
class _CardFoot extends StatelessWidget {
  const new({required this.child});

  /// What the foot holds, keyed by what it is.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    const duration = Duration(milliseconds: 280);
    return ClipRect(
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: const Duration(milliseconds: 140),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .16),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          layoutBuilder: (current, leaving) => Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              // Out of the layout, so the card takes the height of what
              // comes in, and out of reach while it fades.
              for (final child in leaving)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: child),
                ),
              ?current,
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The camera's Bluetooth link as the card's icon shows it.
enum _BluetoothLink {
  /// Not linked, and the scan does not see the camera (or cannot look).
  away,

  /// Not linked, but nearby.
  nearby,

  /// Being linked ([ConnectionController.bleLinking]).
  connecting,

  /// Linked.
  connected;

  static _BluetoothLink of(ConnectionController connection, Presence seen) {
    if (connection.bleLinking) return connecting;
    // The session's own link, which a camera woken for its Wi-Fi drops
    // while the join carries on.
    if (connection.cameraSession?.bleLinked ?? false) return connected;
    return seen == Presence.away ? away : nearby;
  }

  _LinkIcon icon(GrColors c, AppLocalizations l10n) => switch (this) {
    away => _LinkIcon(
      id: 'bluetooth-$name',
      icon: Icons.bluetooth_disabled_rounded,
      color: c.t3,
      label: l10n.camerasLinkAway,
    ),
    nearby => _LinkIcon(
      id: 'bluetooth-$name',
      icon: Icons.bluetooth_disabled_rounded,
      color: c.t2,
      label: l10n.camerasLinkNearby,
    ),
    connecting => _LinkIcon(
      id: 'bluetooth-$name',
      icon: Icons.bluetooth_rounded,
      color: c.t1,
      label: l10n.camerasLinkBluetoothConnecting,
      pulsing: true,
    ),
    connected => _LinkIcon(
      id: 'bluetooth-$name',
      icon: Icons.bluetooth_connected_rounded,
      color: c.ok,
      label: l10n.camerasLinkBluetooth,
    ),
  };
}

/// The camera's Wi-Fi link as the card's icon shows it.
enum _WifiLink {
  /// The phone is not on the camera's Wi-Fi.
  off,

  /// Joining the camera's Wi-Fi, or getting it back after a loss.
  connecting,

  /// On the camera's Wi-Fi.
  connected;

  static _WifiLink of(ConnectionController connection) =>
      switch (connection.status) {
        ConnectionStatus.connecting when connection.step == ConnectStep.wifi =>
          connecting,
        ConnectionStatus.connected =>
          connection.reconnecting ? connecting : connected,
        _ => off,
      };

  _LinkIcon icon(GrColors c, AppLocalizations l10n) => switch (this) {
    off => _LinkIcon(
      id: 'wifi-$name',
      icon: Icons.wifi_off_rounded,
      color: c.t3,
      label: l10n.camerasLinkWifiOff,
    ),
    connecting => _LinkIcon(
      id: 'wifi-$name',
      icon: Icons.wifi_rounded,
      color: c.t1,
      label: l10n.camerasLinkWifiConnecting,
      pulsing: true,
    ),
    connected => _LinkIcon(
      id: 'wifi-$name',
      icon: Icons.wifi_rounded,
      color: c.ok,
      label: l10n.camerasLinkWifi,
    ),
  };
}

/// One of the card's links, as an icon alone; its words are the tooltip
/// and the accessibility label. The icon fades out and in while the link
/// is being made ([pulsing]), and is still when the platform asks for
/// less motion.
class _LinkIcon extends StatefulWidget {
  const new({
    required this.id,
    required this.icon,
    required this.color,
    required this.label,
    this.pulsing = false,
  });

  /// The link and its state, for the icon's key (`camera-card-<id>`).
  final String id;
  final IconData icon;
  final Color color;
  final String label;
  final bool pulsing;

  @override
  State<_LinkIcon> createState() => _LinkIconState();
}

class _LinkIconState extends State<_LinkIcon>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: .2,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_LinkIcon old) {
    super.didUpdateWidget(old);
    if (widget.pulsing != old.pulsing) _syncPulse();
  }

  void _syncPulse() {
    if (!widget.pulsing || MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Tooltip(
      message: widget.label,
      child: Semantics(
        label: widget.label,
        excludeSemantics: true,
        child: Container(
          key: Key('camera-card-${widget.id}'),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.s2,
            shape: BoxShape.circle,
            border: Border.all(color: c.line),
          ),
          child: FadeTransition(
            opacity: _opacity,
            child: Icon(widget.icon, size: 18, color: widget.color),
          ),
        ),
      ),
    );
  }
}

/// Turns the camera on or off ([ConnectionController.powerOn] and
/// [ConnectionController.powerOff]); filled while the camera is on.
class _PowerButton extends StatelessWidget {
  const new({required this.camera, required this.connection, required this.on});

  final SavedCamera camera;
  final ConnectionController connection;

  /// Whether the camera is on; null when unknown, and the button then
  /// turns it on.
  final bool? on;

  Future<void> _press(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final turnOff = on ?? false;
    final done = turnOff
        ? await connection.powerOff()
        : await connection.powerOn();
    // A link that could not be made shows on the card instead, and one
    // that was cancelled needs no word.
    final linked = switch (connection.status) {
      ConnectionStatus.bluetooth || ConnectionStatus.connected => true,
      _ => false,
    };
    if (done || !linked) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          turnOff
              ? l10n.camerasPowerOffFailed(camera.name)
              : l10n.camerasPowerOnFailed(camera.name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final busy = connection.powerChange != null;
    final lit = on ?? false;
    final label = lit
        ? context.l10n.camerasPowerOff(camera.name)
        : context.l10n.camerasPowerOn(camera.name);
    final color = lit ? c.invFg : c.t1;
    final onTap = busy ? null : () => unawaited(_press(context));
    return Tooltip(
      message: label,
      // One node for the button, kept apart from the card's even while it
      // is busy and has no action: the label says what a tap does, so the
      // InkWell's own node, and with it its tap action, is replaced here.
      child: Semantics(
        container: true,
        button: true,
        enabled: !busy,
        toggled: on,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          key: Key('camera-card-power-${lit ? 'on' : 'off'}'),
          color: lit ? c.invBg : c.s2,
          shape: CircleBorder(side: BorderSide(color: lit ? c.invBg : c.line2)),
          child: InkWell(
            key: const Key('camera-card-power'),
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 52,
              child: Center(
                child: busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(
                        Icons.power_settings_new_rounded,
                        size: 24,
                        color: color,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A large button to one of the camera's pages: its icon over its name.
class _PageButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(GrRadii.md),
      side: BorderSide(color: c.line),
    );
    return Material(
      color: c.s2,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: c.t1),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

// ------------------------------------------------------------ other rows

/// `GR IIIx · not nearby` with the presence dot (mock `.near`).
class _NearLabel extends StatelessWidget {
  const new({required this.presence, required this.camera});

  final CameraPresence presence;
  final SavedCamera camera;

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
    final model = camera.modelName;
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
            style: TextStyle(fontSize: 12, color: c.t2),
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
            SizedBox(
              width: 40,
              child: CameraDrawing(body: camera.body, strokeWidth: 1.1),
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
                  _NearLabel(presence: presence, camera: camera),
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
