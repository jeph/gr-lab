import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../connection/camera_pill.dart';
import '../connection/connect_failure_view.dart';
import '../connection/connect_steps.dart';
import '../connection/connection_controller.dart';
import '../data/settings.dart';
import '../theme/tokens.dart';
import 'live_view_controller.dart';
import 'shoot_format.dart';
import 'shoot_model.dart';
import 'shoot_screen.dart';
import 'shoot_widgets.dart';

/// Live view (mock `b-shoot`): laid out like a phone's camera app and
/// always dark. The picture fills the space between the controls, shown
/// whole so that every part of it can be tapped to focus; the exposure
/// readouts edit on a dial; × goes back to Remote.
class LiveViewPage extends StatelessWidget {
  const LiveViewPage({super.key, required this.model});

  final ShootModel model;

  @override
  Widget build(BuildContext context) => Theme(
    data: grTheme(Brightness.dark),
    child: Builder(
      builder: (context) => Scaffold(
        key: const Key('shoot-live'),
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: model.liveView,
          builder: (context, _) => _LiveLayout(model: model),
        ),
      ),
    ),
  );
}

class _LiveLayout extends StatefulWidget {
  const _LiveLayout({required this.model});

  final ShootModel model;

  @override
  State<_LiveLayout> createState() => _LiveLayoutState();
}

class _LiveLayoutState extends State<_LiveLayout> {
  /// The readout whose values the dial shows; null hides the dial.
  String? _dialKey;

  ShootModel get _model => widget.model;
  LiveViewController get _live => _model.liveView;

  static const _readouts = [
    ('av', 'Aperture'),
    ('tv', 'Shutter'),
    ('sv', 'ISO'),
    ('xv', 'EV'),
  ];

  /// A setting the camera lets the app change now: it lists more than one
  /// value (Av lists apertures, not shutter speeds), and for the mode dial
  /// settings the camera has reported them since the dial last moved.
  GrSetting? _editable(String key) {
    if (!_live.modeSettled && LiveViewController.modeSettings.contains(key)) {
      return null;
    }
    final s = _live.props?.setting(key);
    final options = s?.options;
    return options != null && options.length > 1 ? s : null;
  }

  Future<void> _set(String key, String value) async {
    final error = await _live.setSetting(key, value);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _pick(String key, String title) async {
    final s = _editable(key);
    if (s == null) return;
    final value = await showSettingPicker(
      context,
      title: title,
      key: key,
      options: s.options!,
      current: s.current,
    );
    if (value != null && value != s.current) await _set(key, value);
  }

  Future<void> _pickTimer() async {
    final current = _model.driveAndTimer?.$2;
    final picked = await showModalBottomSheet<ShootTimer>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in ShootTimer.values)
              ListTile(
                key: Key('shoot-timer-${t.name}'),
                title: Text(t == ShootTimer.off ? 'Self-timer off' : t.label),
                trailing: t == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(context).pop(t),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _model.setTimer(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final split = _model.driveAndTimer;
    final exposure = _model.exposure;
    final dialKey = _dialKey != null && _editable(_dialKey!) != null
        ? _dialKey
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Picture(model: _model),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: Row(
                  children: [
                    _RoundButton(
                      key: const Key('live-close'),
                      icon: Icons.close_rounded,
                      label: 'Back to Remote',
                      onTap: () => _model.mode = ShootMode.remote,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CameraPill(),
                      ),
                    ),
                    if (exposure != null)
                      Container(
                        key: const Key('live-exposure'),
                        height: 36,
                        constraints: const BoxConstraints(minWidth: 36),
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.s2.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: c.line2),
                        ),
                        child: Text(
                          exposureLabel(exposure),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ShootModeSwitch(
                mode: _model.mode,
                onChanged: (m) => _model.mode = m,
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _Chip(
                      key: const Key('live-chip-drive'),
                      icon: Icons.burst_mode_outlined,
                      label: split?.$1.label ?? '—',
                      onTap: _model.canShoot
                          ? () => unawaited(showDrivePicker(context, _model))
                          : null,
                    ),
                    _Chip(
                      key: const Key('live-chip-timer'),
                      icon: Icons.timer_outlined,
                      label: split?.$2.label ?? '—',
                      onTap:
                          _model.canShoot && split?.$1 != ShootDrive.continuous
                          ? () => unawaited(_pickTimer())
                          : null,
                    ),
                    for (final (key, icon, title) in const [
                      ('meteringMode', Icons.filter_center_focus, 'Metering'),
                      ('effect', Icons.tune_rounded, 'Image Control'),
                    ])
                      if (_live.props?.setting(key)?.current case final v?)
                        _Chip(
                          key: Key('live-chip-$key'),
                          icon: icon,
                          label: settingLabel(key, v),
                          onTap: _editable(key) == null
                              ? null
                              : () => unawaited(_pick(key, title)),
                        ),
                  ],
                ),
              ),
              const Spacer(),
              _Readouts(
                live: _live,
                readouts: _readouts,
                selected: dialKey,
                editable: (k) => _editable(k) != null,
                onTap: (k) =>
                    setState(() => _dialKey = dialKey == k ? null : k),
              ),
              if (dialKey != null)
                _Dial(
                  key: Key('live-dial-$dialKey'),
                  setting: _editable(dialKey)!,
                  onSelect: (v) => unawaited(_set(dialKey, v)),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    _LastShot(bytes: _live.lastShot),
                    Expanded(
                      child: Center(
                        child: ShutterButton(
                          model: _model,
                          size: 80,
                          color: const Color(0xFFF6F4EF),
                          ringGap: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 56),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                volumeShutter
                    ? 'Tap to focus · volume buttons fire the shutter'
                    : 'Tap to focus',
                style: TextStyle(fontSize: 11.5, color: c.t2),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

/// The picture, whole and centred, with the focus mark; or, until frames
/// come, the steps of joining the camera's Wi-Fi or why it failed.
class _Picture extends StatelessWidget {
  const _Picture({required this.model});

  final ShootModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final live = model.liveView;
    final connection = live.connection;
    final failure = connection.failure;
    final camera = connection.camera;
    final phase = live.phase;
    if (phase != LiveViewPhase.streaming) {
      final Widget content;
      if (phase == LiveViewPhase.off) {
        // Turning the camera on first, or it is off.
        content = ShootPowerLine(model: model);
      } else if (phase == LiveViewPhase.joining &&
          failure != null &&
          failure.step == ConnectStep.wifi &&
          camera != null) {
        content = ConnectFailureView(
          camera: camera,
          failure: failure,
          connection: connection,
        );
      } else if (phase == LiveViewPhase.joining) {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Live view comes over ${camera?.name ?? 'the camera'}'s Wi-Fi",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ConnectSteps(connection: connection),
          ],
        );
      } else {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text('Starting live view…', style: TextStyle(color: c.t2)),
          ],
        );
      }
      return Center(
        child: Padding(
          key: Key('live-${phase.name}'),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: content,
        ),
      );
    }
    return ValueListenableBuilder<LiveViewFrame?>(
      valueListenable: live.frame,
      builder: (context, frame, _) {
        if (frame == null) return const SizedBox.shrink();
        final d = frame.dimensions;
        final aspect = d == null || d.height == 0 ? 3 / 2 : d.width / d.height;
        return Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                key: const Key('live-picture'),
                onTapUp: (t) => unawaited(
                  live.focusAt(
                    Offset(
                      t.localPosition.dx / box.maxWidth,
                      t.localPosition.dy / box.maxHeight,
                    ),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      frame.jpeg,
                      gaplessPlayback: true,
                      fit: BoxFit.fill,
                    ),
                    if (live.focus case final f?)
                      _FocusMark(mark: f, size: box.biggest),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusMark extends StatelessWidget {
  const _FocusMark({required this.mark, required this.size});

  final FocusMark mark;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    const side = 72.0;
    final color = switch (mark.state) {
      FocusState.focusing => c.accent,
      FocusState.focused => c.ok,
      FocusState.missed => c.danger,
    };
    return Positioned(
      key: Key('live-focus-${mark.state.name}'),
      left: mark.at.dx * size.width - side / 2,
      top: mark.at.dy * size.height - side / 2,
      width: side,
      height: side,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// Aperture, shutter, ISO and EV; tapping one the camera lets the app change
/// opens the dial for it.
class _Readouts extends StatelessWidget {
  const _Readouts({
    required this.live,
    required this.readouts,
    required this.selected,
    required this.editable,
    required this.onTap,
  });

  final LiveViewController live;
  final List<(String, String)> readouts;
  final String? selected;
  final bool Function(String key) editable;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final props = live.props;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          for (final (key, label) in readouts)
            Expanded(
              child: GestureDetector(
                key: Key('live-readout-$key'),
                behavior: HitTestBehavior.opaque,
                onTap: editable(key) ? () => onTap(key) : null,
                child: Column(
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .6,
                        color: c.t2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      switch (props?.setting(key)?.current) {
                        final v? => settingLabel(key, v),
                        null => '—',
                      },
                      style: GrFonts.monoStyle(
                        context,
                        size: 17,
                        weight: FontWeight.w500,
                        color: key == selected
                            ? c.accent
                            : editable(key)
                            ? c.t1
                            : c.t2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The values of one setting in a row, the current one centred
/// (mock `.dial`).
class _Dial extends StatefulWidget {
  const _Dial({super.key, required this.setting, required this.onSelect});

  final GrSetting setting;
  final ValueChanged<String> onSelect;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> {
  static const _item = 56.0;
  late final ScrollController _scroll;

  int get _index =>
      widget.setting.options!.indexOf(widget.setting.current ?? '');

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: _index < 0 ? 0 : _index * _item,
    );
  }

  @override
  void didUpdateWidget(_Dial old) {
    super.didUpdateWidget(old);
    if (old.setting.current != widget.setting.current && _index >= 0) {
      unawaited(
        _scroll.animateTo(
          _index * _item,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final options = widget.setting.options!;
    final key = widget.setting.key;
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: c.s1.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final pad = (box.maxWidth - _item) / 2;
          return ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemExtent: _item,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final v = options[i];
              final current = v == widget.setting.current;
              final label = settingLabel(key, v).replaceFirst('f/', '');
              return GestureDetector(
                key: Key('live-dial-option-$v'),
                behavior: HitTestBehavior.opaque,
                onTap: current ? null : () => widget.onSelect(v),
                child: Center(
                  child: FittedBox(
                    child: Text(
                      label,
                      style: GrFonts.monoStyle(
                        context,
                        size: 13,
                        weight: current ? FontWeight.w700 : FontWeight.w400,
                        color: current ? c.t1 : c.t2,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: c.s2.withValues(alpha: .8),
        shape: StadiumBorder(side: BorderSide(color: c.line2)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: onTap == null ? c.t3 : c.t1),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GrFonts.monoStyle(
                    context,
                    size: 12.5,
                    color: onTap == null ? c.t2 : c.t1,
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: c.s2.withValues(alpha: .8),
        shape: CircleBorder(side: BorderSide(color: c.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, size: 18, color: c.t1, semanticLabel: label),
          ),
        ),
      ),
    );
  }
}

/// The newest picture taken while live view is on.
class _LastShot extends StatelessWidget {
  const _LastShot({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final b = bytes;
    return Container(
      key: const Key('live-last-shot'),
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line2),
      ),
      child: b == null
          ? null
          : Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}
