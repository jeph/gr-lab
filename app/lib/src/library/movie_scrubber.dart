import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:video_player/video_player.dart';

/// How far [video] has played, as a bar in the theme's accent along the
/// bottom of the movie; a tap or a drag along it seeks.
///
/// It stands in for `video_player`'s `VideoProgressIndicator`, which is red
/// whatever the theme and changes colour under a moving finger: its
/// translucent bar lies over a "buffered" bar that comes and goes with each
/// seek. This one has two opaque colours and no buffered part, as the movie
/// plays from a file on the phone.
class MovieScrubber extends StatefulWidget {
  const new(this.video, {super.key});

  final VideoPlayerController video;

  /// The bar's thickness. The area that takes the finger is [touchHeight].
  static const barHeight = 4.0;
  static const touchHeight = 28.0;

  @override
  State<MovieScrubber> createState() => _MovieScrubberState();
}

class _MovieScrubberState extends State<MovieScrubber> {
  /// The part of the movie last sought, shown until that seek lands: the
  /// player reports where it was until then, and the bar would jump back.
  double? _sought;
  int _seeks = 0;

  /// Whether the movie was playing when the drag began, to go on after it.
  bool _resumeAfterDrag = false;

  static double _played(VideoPlayerValue value) =>
      value.duration > Duration.zero
      ? (value.position.inMicroseconds / value.duration.inMicroseconds).clamp(
          0,
          1,
        )
      : 0;

  Future<void> _seek(Offset touch) async {
    final video = widget.video;
    final fraction = (touch.dx / context.size!.width).clamp(0.0, 1.0);
    final seek = ++_seeks;
    setState(() => _sought = fraction);
    try {
      await video.seekTo(video.value.duration * fraction);
    } finally {
      if (mounted && seek == _seeks) setState(() => _sought = null);
    }
  }

  void _startDrag(DragStartDetails details) {
    final video = widget.video;
    _resumeAfterDrag = video.value.isPlaying;
    if (_resumeAfterDrag) unawaited(video.pause());
    unawaited(_seek(details.localPosition));
  }

  void _endDrag() {
    if (!_resumeAfterDrag) return;
    _resumeAfterDrag = false;
    final video = widget.video;
    // Left at its end, the movie has nothing more to play.
    if ((_sought ?? _played(video.value)) < 1) unawaited(video.play());
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => unawaited(_seek(details.localPosition)),
      onHorizontalDragStart: _startDrag,
      onHorizontalDragUpdate: (details) =>
          unawaited(_seek(details.localPosition)),
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: _endDrag,
      child: SizedBox(
        height: MovieScrubber.touchHeight,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder(
            valueListenable: widget.video,
            builder: (context, value, _) => LinearProgressIndicator(
              value: _sought ?? _played(value),
              minHeight: MovieScrubber.barHeight,
              backgroundColor: c.s4,
              color: c.accent,
            ),
          ),
        ),
      ),
    );
  }
}
