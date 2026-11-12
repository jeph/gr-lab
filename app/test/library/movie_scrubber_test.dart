import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/library/movie_scrubber.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:video_player/video_player.dart';

/// A ten-second movie whose seeks land when the test completes them, as a
/// phone's player lands them some time after they are asked for.
class _Player extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  new()
    : super(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
        ),
      );

  /// Every seek asked for, in order, each landing when completed.
  final seeks = <({Duration position, Completer<void> landed})>[];

  /// Lands every seek still under way.
  void landSeeks() {
    for (final seek in seeks.where((s) => !s.landed.isCompleted)) {
      seek.landed.complete();
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    final landed = Completer<void>();
    seeks.add((position: position, landed: landed));
    await landed.future;
    value = value.copyWith(position: position);
  }

  /// As the real player does, starts over when it is at the movie's end.
  @override
  Future<void> play() async {
    if (value.position == value.duration) await seekTo(Duration.zero);
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> dispose() async => super.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _width = 400.0;

Future<void> _pumpScrubber(
  WidgetTester tester,
  _Player player, {
  GrColors colors = GrColors.light,
}) => tester.pumpWidget(
  MaterialApp(
    theme: grTheme(colors),
    home: Center(
      child: SizedBox(width: _width, child: MovieScrubber(player)),
    ),
  ),
);

LinearProgressIndicator _bar(WidgetTester tester) =>
    tester.widget(find.byType(LinearProgressIndicator));

/// A point [fraction] of the way along the scrubber.
Offset _along(WidgetTester tester, double fraction) {
  final box = tester.getRect(find.byType(MovieScrubber));
  return Offset(box.left + box.width * fraction, box.center.dy);
}

void main() {
  testWidgets('the bar is in the theme, opaque, and follows the player', (
    tester,
  ) async {
    final player = _Player();
    for (final colors in [GrColors.light, GrColors.darkroom]) {
      await _pumpScrubber(tester, player, colors: colors);
      // A change of theme is animated.
      await tester.pumpAndSettle();
      expect(_bar(tester).color, colors.accent);
      expect(_bar(tester).backgroundColor, colors.s4);
      expect(_bar(tester).color!.a, 1);
      expect(_bar(tester).backgroundColor!.a, 1);
    }
    expect(_bar(tester).value, 0);

    player.value = player.value.copyWith(position: const Duration(seconds: 4));
    await tester.pump();
    expect(_bar(tester).value, 0.4);
  });

  testWidgets('the bar stays under the finger until the last seek lands', (
    tester,
  ) async {
    final player = _Player();
    await _pumpScrubber(tester, player);

    final finger = await tester.startGesture(_along(tester, 0.25));
    await tester.pump();
    await finger.moveTo(_along(tester, 0.5));
    await tester.pump();
    await finger.moveTo(_along(tester, 0.75));
    await tester.pump();
    expect(player.seeks.last.position, const Duration(milliseconds: 7500));
    expect(
      player.value.position,
      Duration.zero,
      reason: 'no seek has landed yet',
    );
    expect(_bar(tester).value, 0.75);

    // Earlier seeks land while the finger is already further along: the
    // player reports those positions, and the bar must not go back to them.
    for (final seek in player.seeks.take(player.seeks.length - 1)) {
      seek.landed.complete();
      await tester.pump();
      expect(player.value.position, seek.position);
      expect(_bar(tester).value, 0.75);
    }

    await finger.up();
    player.seeks.last.landed.complete();
    await tester.pump();
    expect(_bar(tester).value, 0.75);

    // The seeks done, the bar shows the player's position again.
    player.value = player.value.copyWith(position: const Duration(seconds: 9));
    await tester.pump();
    expect(_bar(tester).value, 0.9);
  });

  testWidgets('a tap seeks to the point touched', (tester) async {
    final player = _Player();
    await _pumpScrubber(tester, player);

    await tester.tapAt(_along(tester, 0.2));
    await tester.pump();
    expect(player.seeks.single.position, const Duration(seconds: 2));
    expect(_bar(tester).value, 0.2);
  });

  testWidgets('a drag holds a playing movie and lets it go on afterwards, '
      'but not from its end', (tester) async {
    final player = _Player();
    await player.play();
    await _pumpScrubber(tester, player);

    var finger = await tester.startGesture(_along(tester, 0.2));
    await finger.moveTo(_along(tester, 0.5));
    await tester.pump();
    expect(player.value.isPlaying, isFalse);
    await finger.up();
    await tester.pump();
    expect(
      player.value.isPlaying,
      isFalse,
      reason: 'the seek has not landed yet',
    );
    player.landSeeks();
    await tester.pump();
    expect(player.value.isPlaying, isTrue);
    expect(player.value.position, const Duration(seconds: 5));

    finger = await tester.startGesture(_along(tester, 0.5));
    await finger.moveTo(_along(tester, 1.2));
    await tester.pump();
    expect(player.seeks.last.position, const Duration(seconds: 10));
    await finger.up();
    player.landSeeks();
    await tester.pump();
    expect(player.value.isPlaying, isFalse);
    expect(player.value.position, const Duration(seconds: 10));
  });

  testWidgets('a drag to the end and back goes on from where the finger left, '
      'not from the start', (tester) async {
    final player = _Player();
    await player.play();
    await _pumpScrubber(tester, player);

    final finger = await tester.startGesture(_along(tester, 0.5));
    await finger.moveTo(_along(tester, 1.2));
    await tester.pump();
    player.landSeeks();
    await tester.pump();
    expect(player.value.position, const Duration(seconds: 10));

    // The player is still at the end when the finger lifts: the seek back
    // lands later.
    await finger.moveTo(_along(tester, 0.5));
    await finger.up();
    await tester.pump();
    expect(player.value.isPlaying, isFalse);
    player.landSeeks();
    await tester.pump();

    expect(player.value.isPlaying, isTrue);
    expect(player.value.position, const Duration(seconds: 5));
    expect(
      player.seeks.map((s) => s.position),
      isNot(contains(Duration.zero)),
      reason: 'playing must not start the movie over',
    );
  });

  testWidgets('a second drag begun before the first one lands goes on '
      'playing when it ends', (tester) async {
    final player = _Player();
    await player.play();
    await _pumpScrubber(tester, player);

    var finger = await tester.startGesture(_along(tester, 0.2));
    await finger.moveTo(_along(tester, 0.5));
    await finger.up();
    finger = await tester.startGesture(_along(tester, 0.5));
    await finger.moveTo(_along(tester, 0.8));
    await tester.pump();
    player.landSeeks();
    await tester.pump();
    expect(
      player.value.isPlaying,
      isFalse,
      reason: 'the finger is still on the bar',
    );

    await finger.up();
    player.landSeeks();
    await tester.pump();
    expect(player.value.isPlaying, isTrue);
    expect(player.value.position, const Duration(seconds: 8));
  });

  testWidgets('a drag leaves a paused movie paused', (tester) async {
    final player = _Player();
    await _pumpScrubber(tester, player);

    final finger = await tester.startGesture(_along(tester, 0.2));
    await finger.moveTo(_along(tester, 0.5));
    await finger.up();
    await tester.pump();
    expect(player.value.isPlaying, isFalse);
  });
}
