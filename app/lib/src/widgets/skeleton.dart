import 'package:flutter/material.dart';

import 'package:grlab/src/theme/tokens.dart';

/// Stands in for content that is still loading: [child] is built from
/// [SkeletonBox]es and [SkeletonLine]s in the shape of what will replace
/// it, and fades in and out until then. Still when the platform asks for
/// less motion.
class Skeleton extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: .45,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 0;
      _pulse.stop();
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
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: ExcludeSemantics(child: widget.child),
  );
}

/// A block of a [Skeleton], [width] by [height]; as large as its parent
/// allows along a side that is left out.
class SkeletonBox extends StatelessWidget {
  const new({
    super.key,
    this.width = double.infinity,
    this.height = double.infinity,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: GrColors.of(context).s3,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

/// A bar of a [Skeleton] in place of one line of interface text at
/// [fontSize], [width] wide. It takes up the line's height, so the text
/// that replaces it does not move what is around it.
class SkeletonLine extends StatelessWidget {
  const new({required this.width, required this.fontSize, super.key});

  final double width;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: AlignmentDirectional.centerStart,
    children: [
      Text(' ', style: TextStyle(fontSize: fontSize)),
      SkeletonBox(
        width: width,
        height: MediaQuery.textScalerOf(context).scale(fontSize) * .72,
        radius: 4,
      ),
    ],
  );
}
