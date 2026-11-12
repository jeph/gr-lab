import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/camera/camera_top_bar.dart';
import 'package:grphoto/src/connection/camera_pill.dart' show formatBattery;
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/connection/idle_disconnect.dart'
    show IdleDisconnect;
import 'package:grphoto/src/connection/storage_counts.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/pairing/pairing_widgets.dart' show TrailingFit;
import 'package:grphoto/src/shoot/live_view_controller.dart';
import 'package:grphoto/src/shoot/live_view_page.dart';
import 'package:grphoto/src/shoot/shoot_format.dart';
import 'package:grphoto/src/shoot/shoot_model.dart';
import 'package:grphoto/src/shoot/shoot_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';

/// Android delivers the volume buttons to the app as key events; iOS does
/// not, so the hint only promises them on Android.
bool get volumeShutter => defaultTargetPlatform == TargetPlatform.android;

/// The Shoot page: Remote over Bluetooth (mock `b-remote`) or Live view
/// over the camera's Wi-Fi (mock `b-shoot`), with the switch between them
/// at the top of both.
class ShootScreen extends StatefulWidget {
  const new({required this.model, super.key});

  final ShootModel model;

  @override
  State<ShootScreen> createState() => _ShootScreenState();
}

class _ShootScreenState extends State<ShootScreen> {
  late final StreamSubscription<ShootRefusal> _refusals;
  late final AppModels _app = AppScope.of(context);
  VoidCallback? _release;
  bool _started = false;

  ShootModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    _refusals = _model.refusals.listen(_sayRefused);
    HardwareKeyboard.instance.addHandler(_onKey);
    _model.liveView.addListener(_holdWhileStreaming);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _holdWhileStreaming();
    }
  }

  @override
  void dispose() {
    unawaited(_refusals.cancel());
    HardwareKeyboard.instance.removeHandler(_onKey);
    _model.liveView.removeListener(_holdWhileStreaming);
    _release?.call();
    super.dispose();
  }

  void _sayRefused(ShootRefusal refusal) {
    if (!mounted) return;
    final message = shootRefusalMessage(context.l10n, refusal);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Watching live view is use: it keeps the camera's Wi-Fi from being left
  /// for lack of use ([IdleDisconnect]).
  void _holdWhileStreaming() {
    final streaming = _model.liveView.phase == LiveViewPhase.streaming;
    if (streaming && _release == null) {
      _release = _app.idle.hold();
    } else if (!streaming && _release != null) {
      _release!();
      _release = null;
    }
  }

  /// Volume up or down fires the shutter while Shoot is showing.
  bool _onKey(KeyEvent event) {
    if (!_model.visible || event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.audioVolumeUp &&
        key != LogicalKeyboardKey.audioVolumeDown) {
      return false;
    }
    if (_model.canShoot) unawaited(_model.shutter());
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _app.connection]),
    builder: (context, _) => switch (_model.mode) {
      ShootMode.remote => _RemoteView(model: _model),
      ShootMode.liveView => LiveViewPage(model: _model),
    },
  );
}

/// A remote control, not a viewfinder: the camera's mode, shots left and
/// battery, one large shutter, the self-timer and the drive. They are
/// stacked ([_stack]), or in a window too short for that and wide enough
/// (a phone on its side) the shutter goes beside the rest ([_beside]).
class _RemoteView extends StatelessWidget {
  const new({required this.model});

  final ShootModel model;

  /// The shutter is as large as the window allows, between these
  /// \[design\].
  static const _minShutterSize = 96.0;
  static const _maxShutterSize = 168.0;

  /// Height of [_stack] without its shutter, about \[design\].
  static const _stackRestHeight = 400.0;

  /// Height of the shutter's margins and the line under it, about
  /// \[design\].
  static const _shutterRestHeight = 72.0;

  /// A window at least this wide has room for the shutter beside the rest
  /// at text size 100 %; larger text needs a window wider in proportion
  /// \[design\].
  static const _besideWidth = 600.0;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('shoot-remote'),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          // The stack would have to shrink the shutter, then scroll.
          final short = box.maxHeight < _stackRestHeight + _maxShutterSize;
          final wide =
              box.maxWidth >=
              MediaQuery.textScalerOf(context).scale(_besideWidth);
          return short && wide
              ? _beside(context)
              : _stack(context, box.maxHeight);
        },
      ),
    ),
  );

  /// Everything in one column, which scrolls in a window of [height] too
  /// short for it even with the smallest shutter.
  Widget _stack(BuildContext context, double height) => SingleChildScrollView(
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Column(
        // The shutter sits in the middle of the room the rest leaves.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              const CameraTopBar(),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _modeSwitch(),
              ),
              const SizedBox(height: 20),
              _stats(context),
            ],
          ),
          _shutter(context, room: height - _stackRestHeight),
          Column(
            children: [
              _selfTimer(context, labelInline: false),
              _drive(context, bottomMargin: 16),
            ],
          ),
        ],
      ),
    ),
  );

  /// Remote / Live view in the top bar, and under it the readouts, the
  /// self-timer and the drive in one half of the window and the shutter in
  /// the other, each centred in its half. A phone on its side leaves the
  /// halves about 225 of height, so the self-timer's label goes on the
  /// line of its choices. Scrolls under the bar when the taller half does
  /// not fit.
  Widget _beside(BuildContext context) => Column(
    children: [
      CameraTopBar(middle: _modeSwitch()),
      Expanded(
        child: LayoutBuilder(
          builder: (context, halves) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: halves.maxHeight),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _stats(context),
                        const SizedBox(height: 12),
                        _selfTimer(context, labelInline: true),
                        _drive(context, bottomMargin: 0),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _shutter(
                      context,
                      room: halves.maxHeight - _shutterRestHeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _modeSwitch() =>
      ShootModeSwitch(mode: model.mode, onChanged: (m) => model.mode = m);

  /// The camera's mode, the shots left on each of its storages and its
  /// battery, in readouts of one height.
  Widget _stats(BuildContext context) {
    final l10n = context.l10n;
    final exposure = model.exposure;
    final battery = model.battery;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          spacing: 8,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Stat(
                key: const Key('shoot-stat-mode'),
                label: l10n.shootStatMode,
                value: _StatText(
                  exposure == null ? '—' : exposureLabel(l10n, exposure),
                  color: GrColors.of(context).accent,
                ),
              ),
            ),
            Expanded(
              child: _Stat(
                key: const Key('shoot-stat-shots'),
                label: l10n.shootStatShotsLeft,
                value: StorageCounts(
                  storages: model.storages,
                  lineKeyPrefix: 'shoot-stat-shots',
                  soloSize: _StatText.size,
                ),
              ),
            ),
            Expanded(
              child: _Stat(
                key: const Key('shoot-stat-battery'),
                label: l10n.shootStatBattery,
                value: _StatText(
                  battery == null ? '—' : formatBattery(context, battery),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The shutter, as large as [room] allows, over what to do with it.
  Widget _shutter(BuildContext context, {required double room}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShutterButton(
          model: model,
          size: room.clamp(_minShutterSize, _maxShutterSize),
          color: GrColors.of(context).accent,
          ringGap: 10,
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ShootPowerLine(model: model),
        ),
      ],
    ),
  );

  /// The self-timer's choices: under their label, or with [labelInline]
  /// after it on one line.
  Widget _selfTimer(BuildContext context, {required bool labelInline}) {
    final l10n = context.l10n;
    final split = model.driveAndTimer;
    final choices = ShootSegmented<ShootTimer>(
      key: const Key('shoot-timer'),
      values: ShootTimer.values,
      selected: split?.$2,
      label: (t) => t.label(l10n),
      // Continuous drive has no self-timer.
      enabled: model.canShoot && split?.$1 != ShootDrive.continuous,
      onSelect: (t) => unawaited(model.setTimer(t)),
    );
    if (labelInline) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 22, end: 16),
        child: Row(
          children: [
            Expanded(
              child: SectionLabel(
                l10n.shootSelfTimer,
                padding: const EdgeInsetsDirectional.only(end: 12),
              ),
            ),
            Expanded(flex: 3, child: choices),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionLabel(l10n.shootSelfTimer),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: choices,
        ),
      ],
    );
  }

  Widget _drive(BuildContext context, {required double bottomMargin}) {
    final l10n = context.l10n;
    final drive = model.driveAndTimer?.$1;
    return GroupBox(
      margin: EdgeInsets.fromLTRB(16, 12, 16, bottomMargin),
      children: [
        GroupRow(
          key: const Key('shoot-drive'),
          icon: Icons.burst_mode_outlined,
          title: l10n.shootDrive,
          // A drive mode's name is long in some languages (`Fotogramma
          // singolo`): it shrinks rather than push the row off the card.
          trailing: TrailingFit(
            maxWidth: 160,
            child: Text(
              drive?.label(l10n) ??
                  (model.drive == null ? '—' : '${model.drive}'),
              style: TextStyle(fontSize: 15, color: GrColors.of(context).t2),
            ),
          ),
          chevron: true,
          onTap: model.canShoot
              ? () => unawaited(showDrivePicker(context, model))
              : null,
        ),
      ],
    );
  }
}

/// A readout card (mock `.stats`).
class _Stat extends StatelessWidget {
  const new({required this.label, required this.value, super.key});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(GrRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.upperCase(label),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: context.l10n.capitalSpacing(.6),
              color: c.t3,
            ),
          ),
          const SizedBox(height: 6),
          value,
        ],
      ),
    );
  }
}

/// A [_Stat]'s value when it is one short text.
class _StatText extends StatelessWidget {
  const new(this.text, {this.color});

  static const size = 19.0;

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: GrFonts.monoStyle(
      context,
      size: size,
      color: color ?? GrColors.of(context).t1,
    ),
  );
}

/// Under the shutter: what to do, or why it can't be pressed yet.
class ShootPowerLine extends StatelessWidget {
  const new({required this.model, super.key});

  final ShootModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final connection = model.connection;
    final l10n = context.l10n;
    final style = TextStyle(fontSize: 13, color: c.t2);
    final name = connection.camera?.name;
    Widget waiting(String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: c.t2),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: style)),
      ],
    );
    final linking =
        connection.status == ConnectionStatus.connecting &&
        connection.step == ConnectStep.bluetooth;
    if (linking || !model.linked) {
      return waiting(
        name == null
            ? l10n.shootConnectingBluetoothUnnamed
            : l10n.shootConnectingBluetooth(name),
      );
    }
    return switch (model.power) {
      ShootPower.idle || ShootPower.waking => waiting(
        name == null ? l10n.shootTurningOnUnnamed : l10n.shootTurningOn(name),
      ),
      ShootPower.ready when model.countdownEnds != null => Text(
        l10n.shootTapToCancelTimer,
        style: style,
      ),
      ShootPower.ready => Text(
        volumeShutter ? l10n.shootTapToShootVolume : l10n.shootTapToShoot,
        style: style,
      ),
      ShootPower.off || ShootPower.failed => Column(
        key: const Key('shoot-off'),
        children: [
          Text(switch ((model.power, name)) {
            (ShootPower.off, null) => l10n.shootCameraOffUnnamed,
            (ShootPower.off, final name?) => l10n.shootCameraOff(name),
            (_, null) => l10n.shootTurnOnFailedUnnamed,
            (_, final name?) => l10n.shootTurnOnFailed(name),
          }, style: style),
          if (model.powerFailure case final failure?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                shootPowerFailureMessage(l10n, failure),
                key: const Key('shoot-power-failure'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.t3),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('shoot-turn-on'),
            onPressed: model.turnOn,
            child: Text(l10n.shootTurnOn),
          ),
        ],
      ),
    };
  }
}

/// The snack bar for a request the camera refused.
String shootRefusalMessage(AppLocalizations l10n, ShootRefusal refusal) =>
    switch ((refusal.request, refusal.code)) {
      (ShootRequest.shutter, null) => l10n.shootShutterFailed,
      (ShootRequest.shutter, final code?) => l10n.shootShutterFailedCode(code),
      (ShootRequest.driveMode, null) => l10n.shootDriveFailed,
      (ShootRequest.driveMode, final code?) => l10n.shootDriveFailedCode(code),
    };

/// Why the camera did not turn on, under "Couldn't turn … on".
String shootPowerFailureMessage(
  AppLocalizations l10n,
  ShootPowerFailure failure,
) => switch (failure) {
  ShootPowerFailure.bluetoothOff => l10n.shootPowerFailureBluetoothOff,
  ShootPowerFailure.needsPairing => l10n.shootPowerFailureNeedsPairing,
  ShootPowerFailure.linkLost => l10n.shootPowerFailureLinkLost,
  ShootPowerFailure.noAnswer => l10n.shootPowerFailureNoAnswer,
};
