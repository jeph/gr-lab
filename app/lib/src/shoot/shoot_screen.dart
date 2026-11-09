import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final StreamSubscription<String> _messages;
  late final AppModels _app = AppScope.of(context);
  VoidCallback? _release;
  bool _started = false;

  ShootModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    _messages = _model.messages.listen(_say);
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
    unawaited(_messages.cancel());
    HardwareKeyboard.instance.removeHandler(_onKey);
    _model.liveView.removeListener(_holdWhileStreaming);
    _release?.call();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
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
    final split = model.driveAndTimer;
    final timer = split?.$2;
    final drive = split?.$1;
    final ready = model.canShoot;
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
                      label: 'Mode',
                      value: model.exposure == null
                          ? '—'
                          : exposureLabel(model.exposure!),
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      key: const Key('shoot-stat-shots'),
                      label: 'Shots left',
                      value: model.shotsLeft == null
                          ? '—'
                          : _thousands(model.shotsLeft!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      key: const Key('shoot-stat-battery'),
                      label: 'Battery',
                      value: model.battery == null ? '—' : '${model.battery}%',
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
            const SectionLabel('Self-timer'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ShootSegmented<ShootTimer>(
                key: const Key('shoot-timer'),
                values: ShootTimer.values,
                selected: timer,
                label: (t) => t.label,
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
                  title: 'Drive',
                  trailing: Text(
                    drive?.label ??
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

String _thousands(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
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
    final style = TextStyle(fontSize: 13, color: c.t2);
    final name = connection.camera?.name ?? 'the camera';
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
      return waiting('Connecting to $name via Bluetooth…');
    }
    return switch (model.power) {
      ShootPower.idle || ShootPower.waking => waiting('Turning $name on…'),
      ShootPower.ready when model.countdownEnds != null => Text(
        'Tap to cancel the self-timer',
        style: style,
      ),
      ShootPower.ready => Text(
        volumeShutter
            ? 'Tap to shoot · volume buttons work too'
            : 'Tap to shoot',
        style: style,
      ),
      ShootPower.off || ShootPower.failed => Column(
        key: const Key('shoot-off'),
        children: [
          Text(
            model.power == ShootPower.off
                ? '$name is off'
                : "Couldn't turn $name on",
            style: style,
          ),
          if (model.power == ShootPower.failed && model.powerError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                model.powerError!,
                style: GrFonts.monoStyle(context, size: 11, color: c.t3),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('shoot-turn-on'),
            onPressed: model.turnOn,
            child: const Text('Turn on'),
          ),
        ],
      ),
    };
  }
}
