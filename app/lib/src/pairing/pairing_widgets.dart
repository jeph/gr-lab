import 'package:flutter/material.dart';

import 'package:grlab/src/theme/tokens.dart';

/// Round button of the mock top bars (`.iconbtn`), 36 px unless [size]
/// says otherwise.
class GrIconButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.size = 36,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.s2,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 18, color: c.t1),
          ),
        ),
      ),
    );
  }
}

/// Caps a row's trailing control or value so the row title keeps room at
/// large text sizes: values ellipsize, controls shrink.
class TrailingFit extends StatelessWidget {
  const new({required this.child, super.key, this.maxWidth = 130});

  /// A trailing value shown in the secondary text colour, ellipsized.
  static Widget value(BuildContext context, String text) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 130),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13.5, color: GrColors.of(context).t2),
    ),
  );

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: child,
    ),
  );
}

/// Top bar of a pairing page: optional leading and trailing buttons around
/// the `n of 4` counter.
class PairingTopBar extends StatelessWidget {
  const new({required this.step, super.key, this.leading, this.trailing});

  final int step;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
    child: Row(
      children: [
        SizedBox(width: 36, height: 36, child: leading),
        Expanded(
          child: Text(
            '$step of 4',
            textAlign: TextAlign.center,
            style: GrFonts.monoStyle(context),
          ),
        ),
        SizedBox(width: 36, height: 36, child: trailing),
      ],
    ),
  );
}

/// Large title with an explanatory paragraph under it.
class PairingHeadline extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    super.key,
    this.center = false,
  });

  final String title;

  /// Plain text, or spans with [bold] parts for the words the user must
  /// find on screen or on the camera.
  final List<InlineSpan> body;
  final bool center;

  /// A span drawn in the primary text colour and bold.
  static InlineSpan bold(String text) => _BoldSpan(text);

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final align = center ? TextAlign.center : TextAlign.start;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      child: Column(
        crossAxisAlignment: center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: align,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
              height: 1.2,
              color: c.t1,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  for (final span in body)
                    if (span is _BoldSpan)
                      TextSpan(
                        text: span.text,
                        style: TextStyle(
                          color: c.t1,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      span,
                ],
              ),
              textAlign: align,
              style: TextStyle(fontSize: 15, height: 1.5, color: c.t2),
            ),
          ],
        ],
      ),
    );
  }
}

final class _BoldSpan extends TextSpan {
  const new(String text) : super(text: text);
}

/// Concentric rings around a Bluetooth glyph (mock `b-pair-find`).
class RadarHero extends StatelessWidget {
  const new({super.key, this.icon = Icons.bluetooth_rounded});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    Widget ring(double size, Widget child) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.line2),
      ),
      alignment: Alignment.center,
      child: child,
    );
    return Center(
      child: ring(
        180,
        ring(
          124,
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accentSoft,
            ),
            child: Icon(icon, size: 30, color: c.accent),
          ),
        ),
      ),
    );
  }
}

/// A drawing of the camera's rear screen inside a card, so the user knows
/// what to look for on the camera (mock `b-pair`, `b-pair-code`).
class CameraScreenHero extends StatelessWidget {
  const new pairingMenu({super.key}) : _code = false;
  const new authenticationCode({super.key}) : _code = true;

  final bool _code;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    // The camera's own screen is black in both themes.
    const label = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: .4,
      color: Color(0xFFAAAAAA),
    );
    final screen = _code
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('AUTHENTICATION CODE', softWrap: false, style: label),
              const SizedBox(height: 10),
              // Placeholder digits: a sample code could be mistaken for the
              // one to compare.
              Text(
                '• • • • • •',
                softWrap: false,
                style: GrFonts.monoStyle(
                  context,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              _menuItem('OK', selected: true, compact: true),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('PAIRING', softWrap: false, style: label),
              const SizedBox(height: 8),
              _menuItem('Execute Pairing', selected: true),
              const SizedBox(height: 4),
              _menuItem('Paired Devices', selected: false),
            ],
          );
    return Center(
      child: Container(
        width: 250,
        height: 170,
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.line),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 160,
          height: 106,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF050505),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.line2),
          ),
          // Scaled rather than wrapped, so large text settings or other
          // font metrics shrink the drawing instead of overflowing it.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _code ? Alignment.center : Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 134),
              child: IntrinsicWidth(child: screen),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _menuItem(
    String text, {
    required bool selected,
    bool compact = false,
  }) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 7, vertical: 4),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFEDEDED) : const Color(0xFF2A2A2E),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      softWrap: false,
      style: TextStyle(
        fontSize: 10,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? const Color(0xFF111111) : const Color(0xFFDDDDDD),
      ),
    ),
  );
}

/// Tinted round badge with an icon (success check, failure cross).
class StatusBadge extends StatelessWidget {
  const new({
    required this.icon,
    required this.color,
    super.key,
    this.size = 84,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: .17),
    ),
    child: Icon(icon, size: size * .42, color: color),
  );
}

/// Small square tile holding a step number (failure checklists).
class NumberTile extends StatelessWidget {
  const new(this.number, {super.key});

  final int number;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.s3,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$number',
        style: GrFonts.monoStyle(context, size: 13, color: c.t1),
      ),
    );
  }
}

enum GrStepState { done, now, todo }

@immutable
final class GrStep {
  const new(this.title, this.state, {this.detail});

  final String title;
  final GrStepState state;
  final String? detail;
}

/// Vertical progress list with done / current / pending markers (mock
/// `.steps`), used while pairing and while connecting.
class GrStepList extends StatelessWidget {
  const new({required this.steps, super.key});

  final List<GrStep> steps;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: _marker(c, steps[i].state),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      steps[i].title,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: steps[i].state == GrStepState.todo ? c.t3 : c.t1,
                      ),
                    ),
                    if (steps[i].detail case final detail?) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(fontSize: 12.5, color: c.t2),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static Widget _marker(GrColors c, GrStepState state) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: animation, child: child),
    ),
    child: switch (state) {
      GrStepState.done => Container(
        key: const ValueKey(GrStepState.done),
        width: 22,
        height: 22,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.ok),
        child: const Icon(
          Icons.check_rounded,
          size: 14,
          color: Color(0xFF0A0A0B),
        ),
      ),
      GrStepState.now => const _PulsingMarker(key: ValueKey(GrStepState.now)),
      GrStepState.todo => Container(
        key: const ValueKey(GrStepState.todo),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.t3, width: 1.5),
        ),
      ),
    },
  );
}

/// The current step's marker: a dot whose ring keeps expanding and fading
/// while the step runs. Still when the platform asks for less motion.
class _PulsingMarker extends StatefulWidget {
  const new({super.key});

  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 0;
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
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
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = Curves.easeOut.transform(_pulse.value);
              // Grows from the marker's outline to twice its size.
              return Transform.scale(
                scale: 1 + t,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.accent.withValues(alpha: 0.6 * (1 - t)),
                      width: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 22,
            height: 22,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.accent, width: 1.5),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width primary button pinned under a page's content.
class BottomAction extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// Small centred hint at the bottom of a page.
class FootNote extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.45,
        color: GrColors.of(context).t3,
      ),
    ),
  );
}
