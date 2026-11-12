import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/library/library_screen.dart';
import 'package:grphoto/src/services.dart';

import '../support/test_app.dart';

const _jpeg = 'sd1|101RICOH/R0000270';
const _raw = 'sd1|101RICOH/R0000269';

/// The whole app with the fake GR IV paired, its Library open and
/// photo-library saves held back, so a download stays running until the
/// returned gate completes.
Future<(TestApp, Completer<void>)> _inLibrary(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
    ),
  ))!;
  final gate = app.media.gate = Completer<void>();
  await app.pumpApp(tester);
  final library = find.byType(LibraryScreen);
  final button = find.byKey(const Key('camera-card-library'));
  await pumpUntil(
    tester,
    () =>
        library.evaluate().isNotEmpty ||
        button.hitTestable().evaluate().isNotEmpty,
    reason: 'the Library or its button on the camera card',
  );
  if (library.evaluate().isEmpty) await tapWhenReady(tester, button);
  await pumpUntilFound(tester, find.byKey(const ValueKey(_jpeg)));
  return (app, gate);
}

/// Queues the newest JPEG, and with [both] the RAW shot after it.
Future<void> _download(WidgetTester tester, {bool both = false}) async {
  await tester.longPress(find.byKey(const ValueKey(_jpeg)));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('selection-download:jpeg')));
  await tester.pump();
  if (!both) return;
  await tester.longPress(find.byKey(const ValueKey(_raw)));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('selection-download:raw')));
  await tester.pump();
}

void _release(TestApp app, Completer<void> gate) {
  app.media.gate = null;
  gate.complete();
}

void main() {
  testWidgets('a running download is shown outside the app with the '
      "camera's name and its place in the batch, and goes as finished once "
      'it is saved', (tester) async {
    final (app, gate) = await _inLibrary(tester);
    expect(app.background.current, isNull);

    await _download(tester);
    await pumpUntil(tester, () => app.media.held == 1, reason: 'save held');
    await pumpUntil(
      tester,
      () => app.background.current != null,
      reason: 'download shown',
    );
    final shown = app.background.current!;
    expect(shown.paused, isFalse);
    expect(shown.title, 'Downloading');
    expect(shown.detail, startsWith('1 of 1'));
    expect(shown.cameraName, 'GR IV');
    expect(shown.toggleLabel, 'Pause');
    expect(shown.cancelLabel, 'Cancel all');
    expect(shown.channelName, 'Downloads');
    expect(app.background.hides, isEmpty);

    _release(app, gate);
    await pumpUntil(
      tester,
      () => app.background.current == null,
      reason: 'download hidden',
    );
    expect(app.background.hides, [true]);
    expect(app.media.shots.single.names, ['R0000270.JPG']);

    await app.dispose();
  });

  testWidgets('Pause outside the app pauses the queue, which stays shown '
      'as paused, and Resume there runs it to the end', (tester) async {
    final (app, gate) = await _inLibrary(tester);
    await _download(tester, both: true);
    await pumpUntil(tester, () => app.media.held == 1, reason: 'save held');

    app.background.press(BackgroundDownloadAction.pause);
    expect(app.models.downloads.paused, isTrue);
    // The shot the photo library already has is saved; the other waits.
    _release(app, gate);
    await pumpUntil(
      tester,
      () => app.background.current?.detail == '1 left',
      reason: 'one download left, paused',
    );
    final paused = app.background.current!;
    expect(paused.paused, isTrue);
    expect(paused.title, 'Downloads paused');
    expect(paused.toggleLabel, 'Resume');
    await pumpRounds(tester, 20);
    expect(app.media.shots, hasLength(1));
    expect(app.background.hides, isEmpty);

    app.background.press(BackgroundDownloadAction.resume);
    await pumpUntil(
      tester,
      () => app.background.current == null,
      reason: 'download hidden',
    );
    expect(app.background.shown.last.paused, isFalse);
    expect(app.background.hides, [true]);
    expect(app.media.shots, hasLength(2));

    await app.dispose();
  });

  testWidgets('Cancel all outside the app empties the queue and takes the '
      'display down', (tester) async {
    final (app, gate) = await _inLibrary(tester);
    await _download(tester, both: true);
    await pumpUntil(tester, () => app.media.held == 1, reason: 'save held');
    await pumpUntil(
      tester,
      () => app.background.current != null,
      reason: 'download shown',
    );

    app.background.press(BackgroundDownloadAction.cancel);
    _release(app, gate);
    await pumpUntil(
      tester,
      () => app.background.current == null,
      reason: 'download hidden',
    );
    expect(app.models.downloads.jobs, isEmpty);
    // The RAW shot never reached the photo library.
    expect(
      [for (final s in app.media.shots) s.names],
      [
        ['R0000270.JPG'],
      ],
    );

    await app.dispose();
  });

  testWidgets('a queue that ends with a failed download goes as not '
      'finished', (tester) async {
    final (app, gate) = await _inLibrary(tester);
    app.media.failWith = const MediaSaveException(MediaSaveFailure.failed);
    await _download(tester);
    await pumpUntil(
      tester,
      () => app.background.current != null,
      reason: 'download shown',
    );

    _release(app, gate);
    await pumpUntil(
      tester,
      () => app.background.current == null,
      reason: 'download hidden',
    );
    expect(app.models.downloads.failedCount, 1);
    expect(app.background.hides, [false]);

    await app.dispose();
  });

  testWidgets("downloads cut off by the loss of the camera's Wi-Fi are "
      'taken down, since nothing goes on until the user is back', (
    tester,
  ) async {
    final (app, gate) = await _inLibrary(tester);
    await _download(tester, both: true);
    await pumpUntil(tester, () => app.media.held == 1, reason: 'save held');
    await pumpUntil(
      tester,
      () => app.background.current != null,
      reason: 'download shown',
    );

    app.camera.dropWifi(recoverable: false);
    await pumpUntil(
      tester,
      () => app.background.current == null,
      reason: 'download hidden',
    );
    expect(app.background.hides, [false]);
    expect(app.models.downloads.remaining, greaterThan(0));

    _release(app, gate);
    await app.dispose();
  });
}
