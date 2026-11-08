import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../app_scope.dart';
import '../connection/connection_controller.dart';
import '../data/cameras.dart';
import '../theme/tokens.dart';
import '../widgets/group.dart';
import 'cancellable_transport.dart';
import 'nearby_scanner.dart';
import 'pairing_done.dart';
import 'pairing_failure.dart';
import 'pairing_widgets.dart';

enum _Page { find, instructions, pairing, failed }

enum _Bluetooth { checking, ready, off, denied, unsupported, error }

/// Pairs a new camera (mock boards `b-pair-find` … `b-pair-fail`): find it
/// nearby, have the user open Execute Pairing, pair, then hand over to
/// [PairingDoneScreen].
///
/// Used as the app's root while no camera is saved, and pushed as a route
/// to pair another one; as a route it shows a close button and leaves
/// itself on success or cancel. Pairing never retries by itself: the
/// camera's pairing mode is one-shot, so every attempt starts from the
/// user reopening Execute Pairing.
class PairingFlow extends StatefulWidget {
  const PairingFlow({super.key});

  /// Pushes the flow over the current screen.
  static Future<void> push(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const PairingFlow()));

  @override
  State<PairingFlow> createState() => _PairingFlowState();
}

class _PairingFlowState extends State<PairingFlow> {
  late final AppModels _models = AppScope.of(context);

  _Page _page = _Page.find;
  _Bluetooth _bluetooth = _Bluetooth.checking;
  Object? _bluetoothError;
  int _findGeneration = 0;
  NearbyScanner? _scanner;

  NearbyCamera? _selected;
  CancellableTransport? _run;
  GrPairingStage _stage = GrPairingStage.scanning;
  PairingFailureInfo? _failure;

  /// Set when starting to pair dropped the session to the current camera,
  /// so leaving without a new pairing can bring it back.
  bool _droppedSession = false;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkBluetooth(++_findGeneration));
  }

  @override
  void dispose() {
    _findGeneration++;
    _scanner?.dispose();
    final run = _run;
    _run = null;
    if (run != null) unawaited(run.cancel());
    if (_droppedSession && !_paired && _models.cameras.current != null) {
      unawaited(_models.connection.connect());
    }
    super.dispose();
  }

  bool get _isRoute => ModalRoute.of(context)?.isFirst == false;

  String get _cameraName => _selected?.model.shortName ?? 'The camera';

  // ------------------------------------------------------------------ find

  Future<void> _startFinding() async {
    final generation = ++_findGeneration;
    _stopScanner();
    setState(() {
      _page = _Page.find;
      _bluetooth = _Bluetooth.checking;
      _bluetoothError = null;
    });
    await _checkBluetooth(generation);
  }

  Future<void> _checkBluetooth(int generation) async {
    bool current() => mounted && generation == _findGeneration;
    final services = _models.services;
    try {
      if (!await services.ensureBluetoothPermission()) {
        if (current()) setState(() => _bluetooth = _Bluetooth.denied);
        return;
      }
      var state = await services.ble.adapterState();
      // CoreBluetooth reports unknown until its manager has started.
      for (
        var i = 0;
        i < 10 &&
            (state == BleAdapterState.unknown ||
                state == BleAdapterState.resetting);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!current()) return;
        state = await services.ble.adapterState();
      }
      if (!current()) return;
      switch (state) {
        case BleAdapterState.poweredOff:
          setState(() => _bluetooth = _Bluetooth.off);
        case BleAdapterState.unauthorized:
          setState(() => _bluetooth = _Bluetooth.denied);
        case BleAdapterState.unsupported:
          setState(() => _bluetooth = _Bluetooth.unsupported);
        case BleAdapterState.poweredOn ||
            BleAdapterState.unknown ||
            BleAdapterState.resetting:
          setState(() {
            _bluetooth = _Bluetooth.ready;
            _scanner = NearbyScanner(services.ble)..start();
          });
      }
    } on Object catch (e) {
      if (!current()) return;
      setState(() {
        _bluetooth = _Bluetooth.error;
        _bluetoothError = e;
      });
    }
  }

  void _stopScanner() {
    _scanner?.dispose();
    _scanner = null;
  }

  void _select(NearbyCamera camera) {
    _findGeneration++;
    _stopScanner();
    setState(() {
      _selected = camera;
      _page = _Page.instructions;
    });
  }

  // --------------------------------------------------------------- pairing

  Future<void> _pair() async {
    final selected = _selected;
    if (selected == null || _run != null) return;
    final run = CancellableTransport(
      _models.services.ble,
      onlyDeviceId: selected.serial == null ? selected.deviceId : null,
    );
    setState(() {
      _run = run;
      _stage = GrPairingStage.scanning;
      _failure = null;
      _page = _Page.pairing;
    });
    final connection = _models.connection;
    if (connection.status == ConnectionStatus.connecting ||
        connection.status == ConnectionStatus.connected) {
      _droppedSession = true;
    }
    // The session may hold a link to this very camera; pairing needs it.
    await connection.disconnect();
    if (run.cancelled) return;
    final GrPairing pairing;
    try {
      pairing = await pairCamera(
        run,
        clientName: _models.services.clientName,
        serial: selected.serial,
        onStage: (stage) {
          if (mounted && _run == run) setState(() => _stage = stage);
        },
      );
    } on Object catch (e) {
      if (!mounted || run.cancelled) return;
      setState(() {
        _run = null;
        _failure = PairingFailureInfo.from(e, camera: _cameraName);
        _page = _Page.failed;
      });
      return;
    }
    // The ConnectionController opens its own link; the camera may not
    // accept a second one while this stays open.
    try {
      await pairing.client.connection.disconnect();
    } on Object {
      // Already dropped.
    }
    if (!mounted || run.cancelled) return;
    await _finish(pairing.camera);
  }

  Future<void> _finish(GrPairedCamera paired) async {
    _run = null;
    _paired = true;
    final cameras = _models.cameras;
    final existing = cameras.cameras
        .where((c) => c.serial == paired.serialNumber)
        .firstOrNull;
    final saved = SavedCamera(
      paired: paired,
      // Re-pairing a known camera keeps the name the user gave it.
      name: existing?.name ?? SavedCamera.defaultName(paired),
      pairedAt: DateTime.now(),
    );
    final navigator = Navigator.of(context);
    final done = PairingDoneScreen.route(saved.serial);
    // As the root, saving the camera swaps this flow for the Library, so
    // the Done page goes on top of it; as a pushed route it replaces it.
    if (_isRoute) {
      unawaited(navigator.pushReplacement(done));
    } else {
      unawaited(navigator.push(done));
    }
    await cameras.add(saved);
    // Covers re-pairing the current camera, where the camera list keeps
    // the same serial and nothing else starts a connection.
    unawaited(_models.connection.connect());
  }

  /// Stops the running attempt. As a pushed route the flow then closes;
  /// as the root it returns to the instructions, since the next attempt
  /// needs Execute Pairing reopened anyway.
  Future<void> _cancelPairing({bool leave = false}) async {
    final run = _run;
    _run = null;
    if (leave && _isRoute) {
      Navigator.of(context).pop();
    } else {
      setState(() => _page = _Page.instructions);
    }
    await run?.cancel();
  }

  void _pairAgain() => setState(() {
    _failure = null;
    _page = _Page.instructions;
  });

  // ------------------------------------------------------------ navigation

  void _back() {
    switch (_page) {
      case _Page.find:
        if (_isRoute) Navigator.of(context).pop();
      case _Page.instructions || _Page.failed:
        unawaited(_startFinding());
      case _Page.pairing:
        unawaited(_cancelPairing());
    }
  }

  /// Stops a running attempt right away: the route stays mounted during
  /// its exit animation, long enough for a late OK on the camera to finish
  /// pairing and save it.
  void _close() {
    if (_run != null) {
      unawaited(_cancelPairing(leave: true));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRoute = _isRoute;
    final close = isRoute
        ? GrIconButton(
            key: const Key('pairing-close'),
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onPressed: _close,
          )
        : null;
    final back = GrIconButton(
      key: const Key('pairing-back'),
      icon: Icons.arrow_back_rounded,
      tooltip: 'Back',
      onPressed: _back,
    );
    final page = switch (_page) {
      _Page.find => _FindPage(
        leading: close,
        bluetooth: _bluetooth,
        bluetoothError: _bluetoothError,
        scanner: _scanner,
        pairedSerials: {for (final c in _models.cameras.cameras) c.serial},
        onRetry: _startFinding,
        onSelect: _select,
      ),
      _Page.instructions => _InstructionsPage(
        leading: back,
        trailing: close,
        camera: _selected!,
        onPair: _pair,
      ),
      _Page.pairing => _PairingPage(
        leading: back,
        trailing: close,
        cameraName: _cameraName,
        stage: _stage,
        onCancel: () => _cancelPairing(leave: true),
      ),
      _Page.failed => _FailurePage(
        leading: close,
        info: _failure!,
        onPairAgain: _pairAgain,
      ),
    };
    return PopScope(
      canPop: _page == _Page.find,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(body: SafeArea(child: page)),
    );
  }
}

/// Top bar, scrolling content and an optional bottom area.
class _PageLayout extends StatelessWidget {
  const _PageLayout({
    required this.pageKey,
    required this.step,
    required this.leading,
    required this.children,
    this.trailing,
    this.bottom = const [],
  });

  final Key pageKey;
  final int step;
  final Widget? leading;

  /// Close button when the flow is a pushed route and [leading] is Back.
  final Widget? trailing;
  final List<Widget> children;
  final List<Widget> bottom;

  @override
  Widget build(BuildContext context) => Column(
    key: pageKey,
    children: [
      PairingTopBar(step: step, leading: leading, trailing: trailing),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: children,
        ),
      ),
      ...bottom,
    ],
  );
}

// -------------------------------------------------------------------- find

class _FindPage extends StatelessWidget {
  const _FindPage({
    required this.leading,
    required this.bluetooth,
    required this.bluetoothError,
    required this.scanner,
    required this.pairedSerials,
    required this.onRetry,
    required this.onSelect,
  });

  final Widget? leading;
  final _Bluetooth bluetooth;
  final Object? bluetoothError;
  final NearbyScanner? scanner;
  final Set<String> pairedSerials;
  final VoidCallback onRetry;
  final ValueChanged<NearbyCamera> onSelect;

  @override
  Widget build(BuildContext context) => _PageLayout(
    pageKey: const Key('pairing-find'),
    step: 1,
    leading: leading,
    children: [
      const SizedBox(height: 34),
      RadarHero(
        icon: bluetooth == _Bluetooth.ready || bluetooth == _Bluetooth.checking
            ? Icons.bluetooth_rounded
            : Icons.bluetooth_disabled_rounded,
      ),
      const PairingHeadline(
        title: 'Add a camera',
        body: [
          TextSpan(
            text:
                'Turn your GR on and keep it near the phone. Cameras nearby '
                'appear below.',
          ),
        ],
      ),
      ..._status(context),
      const FootNote(
        'Not listed? On the camera, open MENU → E6 Wireless Connection → '
        'Wireless Communication and set Action Mode to On.',
      ),
    ],
  );

  List<Widget> _status(BuildContext context) {
    final c = GrColors.of(context);
    Widget problem(String key, IconData icon, String title, String body) =>
        Padding(
          key: Key(key),
          padding: const EdgeInsets.only(top: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GroupBox(
                children: [GroupRow(icon: icon, title: title, subtitle: body)],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: OutlinedButton(
                  key: const Key('pairing-retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
        );
    switch (bluetooth) {
      case _Bluetooth.checking:
        return [
          const SectionLabel('Nearby'),
          GroupBox(
            children: [
              GroupRow(leading: _spinner(c), title: 'Checking Bluetooth…'),
            ],
          ),
        ];
      case _Bluetooth.off:
        return [
          problem(
            'pairing-bluetooth-off',
            Icons.bluetooth_disabled_rounded,
            'Bluetooth is off',
            'Turn on Bluetooth on this phone, then try again.',
          ),
        ];
      case _Bluetooth.denied:
        return [
          problem(
            'pairing-bluetooth-denied',
            Icons.block_rounded,
            "GR Lab can't use Bluetooth",
            'Allow Bluetooth (on Android: Nearby devices) for GR Lab in the '
                "phone's settings, then try again.",
          ),
        ];
      case _Bluetooth.unsupported:
        return [
          const Padding(
            key: Key('pairing-bluetooth-unsupported'),
            padding: EdgeInsets.only(top: 22),
            child: GroupBox(
              children: [
                GroupRow(
                  icon: Icons.bluetooth_disabled_rounded,
                  title: 'No Bluetooth LE',
                  subtitle:
                      "This phone can't talk to GR cameras over Bluetooth.",
                ),
              ],
            ),
          ),
        ];
      case _Bluetooth.error:
        return [
          problem(
            'pairing-bluetooth-error',
            Icons.error_outline_rounded,
            "Couldn't start Bluetooth",
            '$bluetoothError',
          ),
        ];
      case _Bluetooth.ready:
        final scanner = this.scanner!;
        return [
          const SectionLabel('Nearby'),
          ListenableBuilder(
            listenable: scanner,
            builder: (context, _) => GroupBox(
              children: [
                for (final camera in scanner.cameras)
                  _NearbyRow(
                    camera: camera,
                    paired:
                        camera.serial != null &&
                        pairedSerials.contains(camera.serial),
                    onAdd: () => onSelect(camera),
                  ),
                if (scanner.error case final error?)
                  GroupRow(
                    icon: Icons.error_outline_rounded,
                    title: 'Scanning stopped',
                    subtitle: '$error',
                    trailing: TrailingFit(
                      child: _SmallButton(label: 'Retry', onPressed: onRetry),
                    ),
                  )
                else
                  GroupRow(
                    leading: _spinner(c),
                    title: scanner.cameras.isEmpty
                        ? 'Looking for cameras…'
                        : 'Still looking…',
                  ),
              ],
            ),
          ),
        ];
    }
  }

  static Widget _spinner(GrColors c) => SizedBox(
    width: 32,
    height: 32,
    child: Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.t3),
      ),
    ),
  );
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({
    required this.camera,
    required this.paired,
    required this.onAdd,
  });

  final NearbyCamera camera;
  final bool paired;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final off = camera.powerOn == false;
    final details = [
      ?camera.bluetoothName,
      if (camera.serial case final serial?) 'No. $serial',
    ].join(' · ');
    final note = off
        ? 'Off · turn it on to pair'
        : paired
        ? 'Paired with GR Lab'
        : null;
    return Padding(
      key: Key('nearby-${camera.key}'),
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
            child: Icon(Icons.photo_camera_outlined, size: 18, color: c.t1),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  camera.model.shortName,
                  style: TextStyle(fontSize: 15, color: c.t1),
                ),
                if (details.isNotEmpty)
                  Text(details, style: GrFonts.monoStyle(context, size: 11.5)),
                if (note != null)
                  Text(note, style: TextStyle(fontSize: 12, color: c.t3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _SmallButton(
            key: Key('pair-add-${camera.key}'),
            label: 'Add',
            onPressed: off ? null : onAdd,
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(
        fontFamily: GrFonts.ui,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    child: Text(label),
  );
}

// ------------------------------------------------------------ instructions

class _InstructionsPage extends StatelessWidget {
  const _InstructionsPage({
    required this.leading,
    required this.trailing,
    required this.camera,
    required this.onPair,
  });

  final Widget leading;
  final Widget? trailing;
  final NearbyCamera camera;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final details = [
      ?camera.bluetoothName,
      if (camera.serial case final serial?) 'No. $serial',
    ].join(' · ');
    return _PageLayout(
      pageKey: const Key('pairing-instructions'),
      step: 2,
      leading: leading,
      trailing: trailing,
      bottom: [
        BottomAction(
          children: [
            FilledButton(
              key: const Key('pair-start'),
              onPressed: onPair,
              child: const Text('Pair'),
            ),
          ],
        ),
      ],
      children: [
        const SizedBox(height: 30),
        const CameraScreenHero.pairingMenu(),
        PairingHeadline(
          title: 'Open Execute Pairing on the camera',
          body: [
            const TextSpan(
              text:
                  'MENU → E6 Wireless Connection → Wireless Communication. '
                  'Set Action Mode to On, then Pairing → ',
            ),
            PairingHeadline.bold('Execute Pairing'),
            const TextSpan(text: '. Leave that screen open and tap '),
            PairingHeadline.bold('Pair'),
            const TextSpan(text: ' below.'),
          ],
        ),
        const SizedBox(height: 24),
        GroupBox(
          children: [
            GroupRow(
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.s3,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.check_rounded, size: 18, color: c.ok),
              ),
              title: 'Found ${camera.model.shortName}',
              subtitle: details.isEmpty ? null : details,
            ),
            const GroupRow(
              icon: Icons.bluetooth_rounded,
              title: 'Then confirm a code',
              subtitle:
                  'Your phone will ask you to confirm a code, and the camera '
                  'to press OK',
            ),
          ],
        ),
        const FootNote(
          "Pairing again? Delete this phone from the camera's Paired Devices "
          'first.',
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- pairing

class _PairingPage extends StatelessWidget {
  const _PairingPage({
    required this.leading,
    required this.trailing,
    required this.cameraName,
    required this.stage,
    required this.onCancel,
  });

  final Widget leading;
  final Widget? trailing;
  final String cameraName;
  final GrPairingStage stage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final confirming = stage != GrPairingStage.scanning;
    GrStepState state(GrPairingStage s) => s.index < stage.index
        ? GrStepState.done
        : s == stage
        ? GrStepState.now
        : GrStepState.todo;
    return _PageLayout(
      pageKey: const Key('pairing-progress'),
      step: 3,
      leading: leading,
      trailing: trailing,
      bottom: [
        BottomAction(
          children: [
            OutlinedButton(
              key: const Key('pairing-cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
      children: [
        const SizedBox(height: 30),
        if (confirming)
          const CameraScreenHero.authenticationCode()
        else
          const RadarHero(),
        if (confirming)
          PairingHeadline(
            title: 'Check the code',
            body: [
              const TextSpan(
                text: 'If the code on your phone matches the camera, tap ',
              ),
              PairingHeadline.bold('Pair'),
              const TextSpan(text: ' on the phone, then press '),
              PairingHeadline.bold('OK'),
              const TextSpan(text: ' on the camera.'),
            ],
          )
        else
          PairingHeadline(
            title: 'Connecting to $cameraName',
            body: const [
              TextSpan(text: 'Keep Execute Pairing open on the camera.'),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
          child: GrStepList(
            steps: [
              GrStep(
                'Connecting to $cameraName',
                state(GrPairingStage.scanning),
              ),
              GrStep(
                'Confirm the code',
                state(GrPairingStage.awaitingConfirmation),
                detail: 'Pair on the phone, then OK on the camera',
              ),
              GrStep(
                'Saving the pairing on the camera',
                state(GrPairingStage.registering),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- failure

class _FailurePage extends StatelessWidget {
  const _FailurePage({
    required this.leading,
    required this.info,
    required this.onPairAgain,
  });

  final Widget? leading;
  final PairingFailureInfo info;
  final VoidCallback onPairAgain;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return _PageLayout(
      pageKey: const Key('pairing-failure'),
      step: 3,
      leading: leading,
      bottom: [
        BottomAction(
          children: [
            FilledButton(
              key: const Key('pair-again'),
              onPressed: onPairAgain,
              child: const Text('Pair again'),
            ),
          ],
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              icon: Icons.close_rounded,
              color: c.danger,
              size: 56,
            ),
          ),
        ),
        PairingHeadline(
          title: info.title,
          body: [TextSpan(text: info.body)],
        ),
        const SizedBox(height: 20),
        GroupBox(
          children: [
            for (var i = 0; i < info.steps.length; i++)
              GroupRow(leading: NumberTile(i + 1), title: info.steps[i]),
          ],
        ),
        if (info.hintTitle case final hint?) ...[
          const SizedBox(height: 12),
          GroupBox(
            children: [
              GroupRow(
                icon: Icons.info_outline_rounded,
                title: hint,
                subtitle: info.hintBody,
              ),
            ],
          ),
        ],
        if (info.detail case final detail?)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
            child: Text(
              detail,
              style: GrFonts.monoStyle(context, size: 11, color: c.t3),
            ),
          ),
      ],
    );
  }
}
