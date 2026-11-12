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

  /// Completes when the seek asked for last has landed.
  Future<void> _landing = Future.value();

  /// Whether the movie was playing when the drag began, to go on after it.
  bool _resumeAfterDrag = false;
  int _drags = 0;

  static double _played(VideoPlayerValue value) =>
      value.duration > Duration.zero
      ? (value.position.inMicroseconds / value.duration.inMicroseconds).clamp(
          0,
          1,
        )
      : 0;

  void _seek(Offset touch) {
    final video = widget.video;
    final fraction = (touch.dx / context.size!.width).clamp(0.0, 1.0);
    final seek = ++_seeks;
    setState(() => _sought = fraction);
    _landing = _land(seek, video.value.duration * fraction);
  }

  Future<void> _land(int seek, Duration position) async {
    try {
      await widget.video.seekTo(position);
    } finally {
      if (mounted && seek == _seeks) setState(() => _sought = null);
    }
  }

  void _startDrag(DragStartDetails details) {
    final video = widget.video;
    _drags++;
    // A drag begun while the one before waits to go on playing takes that
    // over.
    _resumeAfterDrag = _resumeAfterDrag || video.value.isPlaying;
    if (video.value.isPlaying) unawaited(video.pause());
    _seek(details.localPosition);
  }

  /// Goes on playing once the drag's last seek has landed. Until then the
  /// player is where an earlier seek left it, and `play` starts a movie
  /// over when that is its end.
  Future<void> _endDrag() async {
    if (!_resumeAfterDrag) return;
    final drag = _drags;
    await _landing;
    if (!mounted || drag != _drags) return;
    _resumeAfterDrag = false;
    final video = widget.video;
    // Left at its end, the movie has nothing more to play.
    if (_played(video.value) < 1) unawaited(video.play());
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _seek(details.localPosition),
      onHorizontalDragStart: _startDrag,
      onHorizontalDragUpdate: (details) => _seek(details.localPosition),
      onHorizontalDragEnd: (_) => unawaited(_endDrag()),
      onHorizontalDragCancel: () => unawaited(_endDrag()),
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
