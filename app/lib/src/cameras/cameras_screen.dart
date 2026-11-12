import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/camera/camera_tab_bar.dart';
import 'package:grphoto/src/camera/camera_top_bar.dart';
import 'package:grphoto/src/cameras/camera_details.dart';
import 'package:grphoto/src/cameras/camera_drawing.dart';
import 'package:grphoto/src/cameras/camera_identity.dart';
import 'package:grphoto/src/cameras/camera_presence.dart';
import 'package:grphoto/src/connection/camera_pill.dart';
import 'package:grphoto/src/connection/camera_sheet.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/connection/link_state.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/geotag/live_geotag_switch.dart';
import 'package:grphoto/src/pairing/pairing_flow.dart';
import 'package:grphoto/src/pairing/pairing_widgets.dart';
import 'package:grphoto/src/sample_photos.dart';
import 'package:grphoto/src/settings/settings_screen.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';

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
              child: const _WelcomePhotos(),
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

/// GR Photo's own photos ([samplePhotos]) one after another, each fading in
/// over the one before \[design\]. Where the phone asks for less motion
/// the next photo takes its place at once.
class _WelcomePhotos extends StatefulWidget {
  const new();

  @override
  State<_WelcomePhotos> createState() => _WelcomePhotosState();
}

class _WelcomePhotosState extends State<_WelcomePhotos>
    with SingleTickerProviderStateMixin {
  /// From one photo starting to fade in to the next doing so, and how
  /// long fading in takes.
  static const Duration _perPhoto = Duration(seconds: 6);
  static const Duration _fadeIn = Duration(milliseconds: 1200);

  /// How far the photo shown has faded in: 1 once it is there alone. The
  /// photos are rebuilt then, which takes away the one underneath.
  late final AnimationController _arrival =
      AnimationController(vsync: this, duration: _fadeIn, value: 1)
        ..addStatusListener((status) {
          if (status.isCompleted) setState(() {});
        });
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _arrival,
    curve: Curves.easeInOut,
  );
  late final Timer _turns;

  /// Which of [samplePhotos] is shown, and which one it is fading in over.
  int _shown = 0;
  int _under = 0;

  bool _decodingAhead = false;

  @override
  void initState() {
    super.initState();
    _turns = Timer.periodic(_perPhoto, (_) => _showNext());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decodingAhead) return;
    _decodingAhead = true;
    _decodeNext();
  }

  /// Decodes the photo after the one shown before its turn, so it fades in
  /// from its start rather than appearing partway through. One at a time:
  /// each is some 11 MB decoded.
  void _decodeNext() {
    final next = samplePhotos[(_shown + 1) % samplePhotos.length];
    unawaited(precacheImage(AssetImage(next.asset), context));
  }

  @override
  void dispose() {
    _turns.cancel();
    _opacity.dispose();
    _arrival.dispose();
    super.dispose();
  }

  void _showNext() {
    setState(() {
      _under = _shown;
      _shown = (_shown + 1) % samplePhotos.length;
    });
    _decodeNext();
    if (MediaQuery.disableAnimationsOf(context)) {
      _arrival.value = 1;
    } else {
      _arrival.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: const Key('cameras-welcome-photos'),
    fit: StackFit.expand,
    children: [
      if (!_arrival.isCompleted)
        KeyedSubtree(key: const ValueKey('under'), child: _photo(_under)),
      FadeTransition(
        key: const ValueKey('shown'),
        opacity: _opacity,
        child: _photo(_shown),
      ),
    ],
  );

  static Widget _photo(int index) => Image.asset(
    samplePhotos[index].asset,
    fit: BoxFit.cover,
    excludeFromSemantics: true,
  );
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
          _CameraCard(
            camera: current,
            presence: presence,
            connection: connection,
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

/// The camera used last (mock `.ccard`, and `connection-controls.html`,
/// direction A): a chip that says how it is linked and opens the camera
/// sheet, where the links are connected and disconnected; a drawing of its
/// model ([CameraDrawing]); its power button and the buttons to its pages
/// ([ConnectionController.tabs]). Nothing on the card moves or gives its
/// place to another control as the connection changes, so a tap lands on
/// what was there when it was aimed \[design\]: Cancel, shown only while
/// Bluetooth is linked for a new connection, has a place of its own that
/// is empty otherwise, and a failure is the chip's words, with its checks
/// in the sheet. Live geotagging's switch ([LiveGeotagSwitch]) comes last,
/// so the button that can come under its line pushes nothing on the card.
class _CameraCard extends StatelessWidget {
  const new({
    required this.camera,
    required this.presence,
    required this.connection,
  });

  final SavedCamera camera;
  final CameraPresence presence;
  final ConnectionController connection;

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

  /// The link as the chip words it: that the camera is being turned on or
  /// off, why the last attempt failed, that the Wi-Fi was left for lack of
  /// use (until the next join), or the link's state in the camera pill's
  /// words.
  Widget _chip(BuildContext context, Presence seen) {
    final l10n = context.l10n;
    void openSheet() => unawaited(showCameraSheet(context));
    final link = _Link.of(connection, seen);
    final state = LinkState.of(connection);
    if (state.changingPower) {
      return _LinkChip(
        link: link,
        label: state.label.text(l10n),
        onTap: openSheet,
      );
    }
    // Bluetooth failures end the link; Wi-Fi ones are kept next to it.
    final failure = switch (connection.status) {
      ConnectionStatus.failed ||
      ConnectionStatus.bluetooth => connection.failure,
      _ => null,
    };
    if (failure != null) {
      return _LinkChip(
        link: _Link.failed,
        label: connectFailureTitle(l10n, failure, camera.name),
        onTap: openSheet,
      );
    }
    final idleFor = connection.idleClosedAfter;
    if (link == _Link.bluetooth && idleFor != null) {
      return _LinkChip(
        link: _Link.idle,
        label: l10n.camerasChipIdle(idleFor.inMinutes),
        onTap: openSheet,
      );
    }
    final battery = connection.cameraStatus?.battery;
    return _LinkChip(
      link: link,
      label: switch (link) {
        _Link.away || _Link.nearby => l10n.connectionPillNotConnected,
        _ => state.label.text(l10n),
      },
      detail: switch (link) {
        _Link.away => l10n.camerasLinkAway,
        _Link.nearby => l10n.camerasLinkNearby,
        _Link.wifi when battery != null => formatBattery(context, battery),
        _ => null,
      },
      onTap: openSheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final seen = presence.of(camera);
    final on = _cameraOn(seen);
    final linking =
        connection.status == ConnectionStatus.connecting &&
        connection.step == ConnectStep.bluetooth;
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
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _chip(context, seen),
                ),
              ),
              const SizedBox(width: 8),
              // Cancel's own place, empty unless Bluetooth is being linked
              // for a new connection.
              SizedBox.square(
                dimension: 36,
                child: linking
                    ? GrIconButton(
                        key: const Key('camera-card-cancel'),
                        icon: Icons.close_rounded,
                        tooltip: l10n.camerasCancel,
                        onPressed: () => unawaited(connection.disconnect()),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              GrIconButton(
                key: const Key('camera-card-more'),
                icon: Icons.more_horiz_rounded,
                tooltip: l10n.camerasDetailsTooltip,
                onPressed: () =>
                    unawaited(CameraDetailsScreen.push(context, camera.serial)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
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
          const SizedBox(height: 16),
          Row(
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
          // A state of its own for each camera: what one refused is not
          // said of the next.
          LiveGeotagSwitch(key: ValueKey(camera.serial), camera: camera),
        ],
      ),
    );
  }
}

/// The camera's link as the card's chip shows it. Wi-Fi counts as a step
/// up from Bluetooth rather than as a second link, so from the join on
/// the chip is the Wi-Fi's, whatever the Bluetooth link under it does.
enum _Link {
  /// The last attempt failed, or a link that was up was lost.
  failed,

  /// Linked over Bluetooth after the Wi-Fi was left for lack of use
  /// ([ConnectionController.idleClosedAfter]).
  idle,

  /// Not linked, and the scan does not see the camera (or cannot look).
  away,

  /// Not linked, but nearby. A camera that is off and that the session
  /// let go of ([ConnectionController.parked]) is not linked either: the
  /// chip says how the camera is linked, and the power button whether it
  /// is on.
  nearby,

  /// Bluetooth is being linked ([ConnectionController.bleLinking]).
  bluetoothConnecting,

  /// Linked over Bluetooth.
  bluetooth,

  /// Joining the camera's Wi-Fi, or getting it back after a loss.
  wifiConnecting,

  /// On the camera's Wi-Fi.
  wifi;

  static _Link of(ConnectionController connection, Presence seen) {
    final onWifi = connection.status == ConnectionStatus.connected;
    final joining =
        connection.status == ConnectionStatus.connecting &&
        connection.step == ConnectStep.wifi;
    if (joining || (onWifi && connection.reconnecting)) return wifiConnecting;
    if (onWifi) return wifi;
    if (connection.bleLinking) return bluetoothConnecting;
    if (connection.bleLinked) return bluetooth;
    return seen == Presence.away ? away : nearby;
  }

  IconData get icon => switch (this) {
    failed => Icons.error_outline_rounded,
    idle => Icons.timer_outlined,
    away || nearby => Icons.bluetooth_disabled_rounded,
    bluetoothConnecting => Icons.bluetooth_rounded,
    bluetooth => Icons.bluetooth_connected_rounded,
    wifiConnecting || wifi => Icons.wifi_rounded,
  };

  Color iconColor(GrColors c) => switch (this) {
    failed => c.danger,
    idle => c.accent,
    away => c.t3,
    nearby => c.t2,
    bluetoothConnecting || wifiConnecting => c.t1,
    bluetooth || wifi => c.ok,
  };

  /// The link is being made: the chip's icon pulses.
  bool get pulsing => this == bluetoothConnecting || this == wifiConnecting;
}

/// The card's link in words, with [detail] (whether the camera is nearby,
/// its battery) in small type after them; a tap opens the camera sheet.
/// As tall as the round buttons beside it, and never wider than the room
/// they leave: the words are cut short instead. The icon fades out and in
/// while the link is being made ([_Link.pulsing]), and is still when the
/// platform asks for less motion.
class _LinkChip extends StatefulWidget {
  const new({
    required this.link,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final _Link link;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  State<_LinkChip> createState() => _LinkChipState();
}

class _LinkChipState extends State<_LinkChip>
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
  void didUpdateWidget(_LinkChip old) {
    super.didUpdateWidget(old);
    if (widget.link.pulsing != old.link.pulsing) _syncPulse();
  }

  void _syncPulse() {
    if (!widget.link.pulsing || MediaQuery.disableAnimationsOf(context)) {
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
    final link = widget.link;
    // A failure and the idle note stand out from the link's plain states.
    final tint = switch (link) {
      _Link.failed => c.danger,
      _Link.idle => c.accent,
      _ => null,
    };
    final detail = widget.detail;
    return Semantics(
      button: true,
      child: Material(
        key: Key('camera-card-link-${link.name}'),
        color: tint == null
            ? c.s2
            : Color.alphaBlend(tint.withValues(alpha: .12), c.s1),
        shape: StadiumBorder(
          side: BorderSide(color: tint?.withValues(alpha: .36) ?? c.line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.onTap,
          // Grows with large text instead of clipping it.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 11, end: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _opacity,
                    child: Icon(link.icon, size: 17, color: link.iconColor(c)),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: widget.label,
                        children: [
                          if (detail != null)
                            TextSpan(
                              text: '  $detail',
                              style: GrFonts.monoStyle(context, size: 11.5),
                            ),
                        ],
                      ),
                      key: const Key('camera-card-link-words'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: link == _Link.failed ? c.danger : c.t1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.t3),
                ],
              ),
            ),
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
