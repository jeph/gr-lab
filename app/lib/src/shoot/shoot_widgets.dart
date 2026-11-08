import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../theme/tokens.dart';
import 'shoot_format.dart';
import 'shoot_model.dart';

/// Remote / Live view, at the top of Shoot in both modes (mock `.modeseg`).
class ShootModeSwitch extends StatelessWidget {
  const ShootModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final ShootMode mode;
  final ValueChanged<ShootMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      key: const Key('shoot-mode'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.s2.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (m, icon, label) in const [
            (ShootMode.remote, Icons.bluetooth_rounded, 'Remote'),
            (ShootMode.liveView, Icons.wifi_rounded, 'Live view'),
          ])
            Semantics(
              button: true,
              selected: m == mode,
              excludeSemantics: true,
              label: label,
              child: GestureDetector(
                key: Key('shoot-mode-${m.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: m == mode ? c.s4 : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: m == mode ? c.t1 : c.t2),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: m == mode ? c.t1 : c.t2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row of equal choices (mock `.segc`).
class ShootSegmented<T> extends StatelessWidget {
  const ShootSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.enabled = true,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            for (final v in values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: v == selected,
                  child: GestureDetector(
                    key: ValueKey('shoot-seg-$v'),
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled ? () => onSelect(v) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: v == selected ? c.s4 : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label(v),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: v == selected ? c.t1 : c.t2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The shutter. While a self-timer runs it is a ring counting down the
/// seconds left, and tapping it cancels (mock `b-remote` notes).
class ShutterButton extends StatefulWidget {
  const ShutterButton({
    super.key,
    required this.model,
    required this.size,
    required this.color,
    required this.ringGap,
  });

  final ShootModel model;
  final double size;
  final Color color;

  /// Space between the outer ring and the filled disc.
  final double ringGap;

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
    _onModel();
  }

  @override
  void didUpdateWidget(ShutterButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.model, widget.model)) {
      old.model.removeListener(_onModel);
      widget.model.addListener(_onModel);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    _tick?.cancel();
    super.dispose();
  }

  void _onModel() {
    final counting = widget.model.countdownEnds != null;
    if (counting && _tick == null) {
      _tick = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => setState(() {}),
      );
    } else if (!counting && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final model = widget.model;
    final ends = model.countdownEnds;
    final length = model.countdown;
    final size = widget.size;
    final enabled = model.canShoot;
    final Widget face;
    final String label;
    if (ends != null && length != null) {
      final left = ends.difference(DateTime.now());
      final fraction = length.inMilliseconds == 0
          ? 0.0
          : (left.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
      final seconds = math.max(0, (left.inMilliseconds / 1000).ceil());
      label = 'Cancel self-timer, $seconds seconds left';
      face = CustomPaint(
        key: const Key('shoot-countdown'),
        painter: _RingPainter(
          fraction: fraction,
          color: widget.color,
          track: c.line2,
          width: 6,
        ),
        child: Center(
          child: Text(
            '$seconds',
            style: GrFonts.monoStyle(
              context,
              size: size * .3,
              color: widget.color,
              weight: FontWeight.w500,
            ),
          ),
        ),
      );
    } else {
      label = 'Shutter';
      face = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: widget.color, width: 4),
        ),
        child: Padding(
          padding: EdgeInsets.all(widget.ringGap),
          child: AnimatedScale(
            scale: model.capturing ? .88 : 1,
            duration: const Duration(milliseconds: 120),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: model.capturing
                    ? widget.color.withValues(alpha: .6)
                    : widget.color,
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('shoot-shutter'),
        onTap: enabled ? () => unawaited(model.shutter()) : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : .35,
          duration: const Duration(milliseconds: 200),
          child: SizedBox.square(dimension: size, child: face),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.width,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// Picks a drive mode (bottom sheet). [current] is checked.
Future<void> showDrivePicker(BuildContext context, ShootModel model) async {
  final current = model.driveAndTimer?.$1;
  final picked = await showModalBottomSheet<ShootDrive>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        key: const Key('shoot-drive-sheet'),
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Drive',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          for (final d in ShootDrive.values)
            ListTile(
              key: Key('shoot-drive-${d.name}'),
              title: Text(d.label),
              trailing: d == current ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop(d),
            ),
        ],
      ),
    ),
  );
  if (picked != null) await model.setDrive(picked);
}

/// Picks one of [options] for a `/v1/props` setting (bottom sheet).
Future<String?> showSettingPicker(
  BuildContext context, {
  required String title,
  required String key,
  required List<String> options,
  required String? current,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .6,
      ),
      child: ListView(
        key: Key('shoot-setting-sheet-$key'),
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          for (final o in options)
            ListTile(
              key: Key('shoot-option-$key-$o'),
              title: Text(settingLabel(key, o)),
              trailing: o == current ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop(o),
            ),
        ],
      ),
    ),
  ),
);
