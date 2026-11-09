import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/pairing/pairing_done.dart';
import 'package:grlab/src/pairing/pairing_failure.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

enum _Page { find, instructions, pairing, failed }

enum _Bluetooth { checking, ready, off, denied, unsupported, error }

/// Pairs a new camera (mock boards `b-pair-find` … `b-pair-fail`): find it
/// nearby, have the user open Execute Pairing, pair, then hand over to
/// [PairingDoneScreen].
///
/// Pushed over the Cameras screen; it shows a close button and leaves
/// itself on success or cancel. Pairing never retries by itself: the
/// camera's pairing mode is one-shot, so every attempt starts from the
/// user reopening Execute Pairing.
class PairingFlow extends StatefulWidget {
  const new({super.key});

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
  PairingRun? _run;
  GrPairingStage _stage = GrPairingStage.scanning;

  /// Why the last attempt failed; the failure page maps it to messages.
  Object? _pairingError;

  /// Set when starting to pair dropped the session to the current camera
  /// (connecting, or linked over Bluetooth or Wi-Fi), so leaving without a
  /// new pairing can bring it back.
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
    // The session comes back once the run has let go of its link.
    final released = run?.cancel() ?? Future<void>.value();
    if (_droppedSession && !_paired && _models.cameras.current != null) {
      unawaited(released.whenComplete(_models.connection.connect));
    }
    super.dispose();
  }

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
    final camera = _models.services.camera;
    try {
      // A denied permission reads as unauthorized.
      final state = await camera.bluetoothState(waitForStartup: true);
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
            _scanner = NearbyScanner(camera)..start();
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
    final run = PairingRun(
      _models.services.camera,
      target: selected,
      clientName: _models.services.clientName,
    );
    setState(() {
      _run = run;
      _stage = GrPairingStage.scanning;
      _pairingError = null;
      _page = _Page.pairing;
    });
    final connection = _models.connection;
    switch (connection.status) {
      case ConnectionStatus.connecting ||
          ConnectionStatus.bluetooth ||
          ConnectionStatus.connected:
        _droppedSession = true;
      case ConnectionStatus.offline || ConnectionStatus.failed:
        break;
    }
    // The session may hold a link to this very camera; pairing needs it.
    await connection.disconnect();
    if (run.cancelled) return;
    final GrPairedCamera paired;
    try {
      paired = await run.start(
        onStage: (stage) {
          if (mounted && _run == run) setState(() => _stage = stage);
        },
      );
    } on Object catch (e) {
      if (!mounted || run.cancelled) return;
      setState(() {
        _run = null;
        _pairingError = e;
        _page = _Page.failed;
      });
      return;
    }
    if (!mounted || run.cancelled) return;
    await _finish(paired);
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
    Navigator.of(context)
        .pushReplacement(PairingDoneScreen.route(saved.serial));
    await cameras.add(saved);
    // Connects to the new camera, which saving made the current one; the
    // Cameras screen shows the steps once Done is pressed.
    unawaited(_models.connection.connect());
  }

  /// Stops the running attempt. Leaving closes the flow; otherwise it
  /// returns to the instructions, since the next attempt needs Execute
  /// Pairing reopened anyway.
  Future<void> _cancelPairing({bool leave = false}) async {
    final run = _run;
    _run = null;
    if (leave) {
      Navigator.of(context).pop();
    } else {
      setState(() => _page = _Page.instructions);
    }
    await run?.cancel();
  }

  void _pairAgain() => setState(() {
    _pairingError = null;
    _page = _Page.instructions;
  });

  // ------------------------------------------------------------ navigation

  void _back() {
    switch (_page) {
      case _Page.find:
        Navigator.of(context).pop();
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
    final close = GrIconButton(
      key: const Key('pairing-close'),
      icon: Icons.close_rounded,
      tooltip: context.l10n.pairingClose,
      onPressed: _close,
    );
    final back = GrIconButton(
      key: const Key('pairing-back'),
      icon: Icons.arrow_back_rounded,
      tooltip: context.l10n.pairingBack,
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
        pairAt: _nextAttemptAt(),
        onPair: _pair,
      ),
      _Page.pairing => _PairingPage(
        leading: back,
        trailing: close,
        cameraName: _selected!.model.shortName,
        stage: _stage,
        onCancel: () => _cancelPairing(leave: true),
      ),
      _Page.failed => _FailurePage(
        leading: close,
        error: _pairingError!,
        cameraName: _selected!.model.shortName,
        pairAt: _nextAttemptAt(),
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

  /// When the selected camera accepts the next pairing attempt; null when
  /// it does now.
  DateTime? _nextAttemptAt() =>
      PairingRun.nextAttemptAt(_models.services.camera, _selected!);
}

/// Builds with the whole seconds left until [until], rebuilding each
/// second; null once it passed (or when there is no [until]).
class _Countdown extends StatefulWidget {
  const new({required this.until, required this.builder});

  final DateTime? until;
  final Widget Function(BuildContext context, int? secondsLeft) builder;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _tick;

  Duration? get _left {
    final until = widget.until;
    if (until == null) return null;
    final left = until.difference(clock.now());
    return left > Duration.zero ? left : null;
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Rebuilds when the shown number of seconds next changes.
  void _schedule() {
    _tick?.cancel();
    _tick = null;
    final left = _left;
    if (left == null) return;
    final ms = left.inMilliseconds % 1000;
    _tick = Timer(Duration(milliseconds: ms == 0 ? 1000 : ms), () {
      if (!mounted) return;
      setState(_schedule);
    });
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final seconds = left == null ? null : (left.inMilliseconds / 1000).ceil();
    return widget.builder(context, seconds);
  }
}

/// Top bar, scrolling content and an optional bottom area.
class _PageLayout extends StatelessWidget {
  const new({
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
  const new({
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _PageLayout(
      pageKey: const Key('pairing-find'),
      step: 1,
      leading: leading,
      children: [
        const SizedBox(height: 34),
        RadarHero(
          icon:
              bluetooth == _Bluetooth.ready || bluetooth == _Bluetooth.checking
              ? Icons.bluetooth_rounded
              : Icons.bluetooth_disabled_rounded,
        ),
        PairingHeadline(
          title: l10n.pairingFindTitle,
          body: l10n.pairingFindBody,
        ),
        ..._status(context),
        FootNote(l10n.pairingFindNotListed),
      ],
    );
  }

  /// What the find page says about a Bluetooth or scan [error].
  static String _errorText(AppLocalizations l10n, Object error) =>
      switch (error) {
        BleException(code: BleErrorCode.poweredOff) =>
          l10n.pairingBluetoothOffBody,
        BleException(code: BleErrorCode.unauthorized) =>
          l10n.pairingBluetoothDeniedBody,
        _ => l10n.pairingErrorCode(PairingFailureInfo.errorCode(error)),
      };

  List<Widget> _status(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
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
                  child: Text(l10n.pairingTryAgain),
                ),
              ),
            ],
          ),
        );
    switch (bluetooth) {
      case _Bluetooth.checking:
        return [
          SectionLabel(l10n.pairingNearbySection),
          GroupBox(
            children: [
              GroupRow(
                leading: _spinner(c),
                title: l10n.pairingCheckingBluetooth,
              ),
            ],
          ),
        ];
      case _Bluetooth.off:
        return [
          problem(
            'pairing-bluetooth-off',
            Icons.bluetooth_disabled_rounded,
            l10n.pairingBluetoothOffTitle,
            l10n.pairingBluetoothOffBody,
          ),
        ];
      case _Bluetooth.denied:
        return [
          problem(
            'pairing-bluetooth-denied',
            Icons.block_rounded,
            l10n.pairingBluetoothDeniedTitle,
            l10n.pairingBluetoothDeniedBody,
          ),
        ];
      case _Bluetooth.unsupported:
        return [
          Padding(
            key: const Key('pairing-bluetooth-unsupported'),
            padding: const EdgeInsets.only(top: 22),
            child: GroupBox(
              children: [
                GroupRow(
                  icon: Icons.bluetooth_disabled_rounded,
                  title: l10n.pairingBluetoothUnsupportedTitle,
                  subtitle: l10n.pairingBluetoothUnsupportedBody,
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
            l10n.pairingBluetoothErrorTitle,
            _errorText(l10n, bluetoothError!),
          ),
        ];
      case _Bluetooth.ready:
        final scanner = this.scanner!;
        return [
          SectionLabel(l10n.pairingNearbySection),
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
                    title: l10n.pairingScanStopped,
                    subtitle: _errorText(l10n, error),
                    trailing: TrailingFit(
                      child: _SmallButton(
                        label: l10n.pairingRetry,
                        onPressed: onRetry,
                      ),
                    ),
                  )
                else
                  GroupRow(
                    leading: _spinner(c),
                    title: scanner.cameras.isEmpty
                        ? l10n.pairingLookingForCameras
                        : l10n.pairingStillLooking,
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

/// The Bluetooth name and serial number a nearby [camera] advertises, as
/// one line, or null when it advertises neither.
String? _cameraDetails(AppLocalizations l10n, NearbyCamera camera) =>
    switch ((camera.bluetoothName, camera.serial)) {
      (final name?, final serial?) => l10n.pairingNameAndSerial(name, serial),
      (null, final serial?) => l10n.pairingSerialNumber(serial),
      (final name?, null) => name,
      (null, null) => null,
    };

class _NearbyRow extends StatelessWidget {
  const new({required this.camera, required this.paired, required this.onAdd});

  final NearbyCamera camera;
  final bool paired;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final off = camera.powerOn == false;
    final details = _cameraDetails(l10n, camera);
    final note = off
        ? l10n.pairingNearbyOff
        : paired
        ? l10n.pairingNearbyPaired
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
                if (details != null)
                  Text(details, style: GrFonts.monoStyle(context, size: 11.5)),
                if (note != null)
                  Text(note, style: TextStyle(fontSize: 12, color: c.t3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _SmallButton(
            key: Key('pair-add-${camera.key}'),
            label: l10n.pairingAdd,
            onPressed: off ? null : onAdd,
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const new({required this.label, super.key, this.onPressed});

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
  const new({
    required this.leading,
    required this.trailing,
    required this.camera,
    required this.pairAt,
    required this.onPair,
  });

  final Widget leading;
  final Widget? trailing;
  final NearbyCamera camera;

  /// When the camera accepts the next attempt; Pair is off until then.
  final DateTime? pairAt;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) =>
      _Countdown(until: pairAt, builder: _build);

  Widget _build(BuildContext context, int? wait) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
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
              onPressed: wait == null ? onPair : null,
              child: Text(l10n.pairingPair),
            ),
          ],
        ),
      ],
      children: [
        const SizedBox(height: 30),
        const CameraScreenHero.pairingMenu(),
        PairingHeadline(
          title: l10n.pairingInstructionsTitle,
          body: l10n.pairingInstructionsBody,
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
              title: l10n.pairingFoundCamera(camera.model.shortName),
              subtitle: _cameraDetails(l10n, camera),
            ),
            GroupRow(
              icon: Icons.bluetooth_rounded,
              title: l10n.pairingConfirmCodeTitle,
              subtitle: l10n.pairingConfirmCodeBody,
            ),
          ],
        ),
        if (wait != null) ...[const SizedBox(height: 12), _RetryWait(wait)],
        FootNote(l10n.pairingInstructionsPairingAgain),
      ],
    );
  }
}

/// How long the next pairing attempt has to wait.
class _RetryWait extends StatelessWidget {
  const new(this.seconds);

  final int seconds;

  @override
  Widget build(BuildContext context) => GroupBox(
    key: const Key('pairing-retry-wait'),
    children: [
      GroupRow(
        icon: Icons.schedule_rounded,
        title: context.l10n.pairingRetryWait(seconds),
      ),
    ],
  );
}

// ----------------------------------------------------------------- pairing

class _PairingPage extends StatelessWidget {
  const new({
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
    final l10n = context.l10n;
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
              child: Text(l10n.pairingCancel),
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
            title: l10n.pairingCheckCodeTitle,
            body: l10n.pairingCheckCodeBody,
          )
        else
          PairingHeadline(
            title: l10n.pairingConnectingTo(cameraName),
            body: l10n.pairingConnectingBody,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
          child: GrStepList(
            steps: [
              GrStep(
                l10n.pairingConnectingTo(cameraName),
                state(GrPairingStage.scanning),
              ),
              GrStep(
                l10n.pairingStageConfirm,
                state(GrPairingStage.awaitingConfirmation),
                detail: l10n.pairingStageConfirmDetail,
              ),
              GrStep(
                l10n.pairingStageRegister,
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
  const new({
    required this.leading,
    required this.error,
    required this.cameraName,
    required this.pairAt,
    required this.onPairAgain,
  });

  final Widget? leading;

  /// What `pairCamera` threw.
  final Object error;
  final String cameraName;

  /// When the camera accepts the next attempt, shown until then.
  final DateTime? pairAt;
  final VoidCallback onPairAgain;

  @override
  Widget build(BuildContext context) =>
      _Countdown(until: pairAt, builder: _build);

  Widget _build(BuildContext context, int? wait) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final info = PairingFailureInfo.from(error, camera: cameraName, l10n: l10n);
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
              child: Text(l10n.pairingPairAgain),
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
        PairingHeadline(title: info.title, body: info.body),
        const SizedBox(height: 20),
        GroupBox(
          children: [
            for (var i = 0; i < info.steps.length; i++)
              GroupRow(leading: NumberTile(i + 1), title: info.steps[i]),
          ],
        ),
        if (wait != null) ...[const SizedBox(height: 12), _RetryWait(wait)],
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
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
          child: Text(
            info.detail,
            style: GrFonts.monoStyle(context, size: 11, color: c.t3),
          ),
        ),
      ],
    );
  }
}
