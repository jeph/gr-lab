import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/camera/camera_top_bar.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/connection/idle_disconnect.dart' show IdleDisconnect;
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/shoot/live_view_controller.dart';
import 'package:grlab/src/shoot/live_view_page.dart';
import 'package:grlab/src/shoot/shoot_format.dart';
import 'package:grlab/src/shoot/shoot_model.dart';
import 'package:grlab/src/shoot/shoot_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';
import 'package:intl/intl.dart';

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
/// battery, one large shutter, the self-timer and the drive.
class _RemoteView extends StatelessWidget {
  const new({required this.model});

  final ShootModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final split = model.driveAndTimer;
    final timer = split?.$2;
    final drive = split?.$1;
    final ready = model.canShoot;
    final exposure = model.exposure;
    final shotsLeft = model.shotsLeft;
    final battery = model.battery;
    return Scaffold(
      key: const Key('shoot-remote'),
      body: SafeArea(
        child: Column(
          children: [
            const CameraTopBar(),
            const SizedBox(height: 14),
            ShootModeSwitch(mode: model.mode, onChanged: (m) => model.mode = m),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      key: const Key('shoot-stat-mode'),
                      label: l10n.shootStatMode,
                      value: exposure == null
                          ? '—'
                          : exposureLabel(l10n, exposure),
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      key: const Key('shoot-stat-shots'),
                      label: l10n.shootStatShotsLeft,
                      value: shotsLeft == null
                          ? '—'
                          : NumberFormat.decimalPattern(locale)
                                .format(shotsLeft),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      key: const Key('shoot-stat-battery'),
                      label: l10n.shootStatBattery,
                      value: battery == null
                          ? '—'
                          : NumberFormat.percentPattern(locale)
                                .format(battery / 100),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShutterButton(
                    model: model,
                    size: 168,
                    color: c.accent,
                    ringGap: 10,
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ShootPowerLine(model: model),
                  ),
                ],
              ),
            ),
            SectionLabel(l10n.shootSelfTimer),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ShootSegmented<ShootTimer>(
                key: const Key('shoot-timer'),
                values: ShootTimer.values,
                selected: timer,
                label: (t) => t.label(l10n),
                // Continuous drive has no self-timer.
                enabled: ready && drive != ShootDrive.continuous,
                onSelect: (t) => unawaited(model.setTimer(t)),
              ),
            ),
            GroupBox(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                GroupRow(
                  key: const Key('shoot-drive'),
                  icon: Icons.burst_mode_outlined,
                  title: l10n.shootDrive,
                  trailing: Text(
                    drive?.label(l10n) ??
                        (model.drive == null ? '—' : '${model.drive}'),
                    style: TextStyle(fontSize: 15, color: c.t2),
                  ),
                  chevron: true,
                  onTap: ready
                      ? () => unawaited(showDrivePicker(context, model))
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A readout card (mock `.stats`).
class _Stat extends StatelessWidget {
  const new({required this.label, required this.value, super.key, this.color});

  final String label;
  final String value;
  final Color? color;

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
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .6,
              color: c.t3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GrFonts.monoStyle(context, size: 19, color: color ?? c.t1),
          ),
        ],
      ),
    );
  }
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
