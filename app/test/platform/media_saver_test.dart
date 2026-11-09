import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/platform/media_saver.dart';
import 'package:grlab/src/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.jeph.grlab/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) reply;

  setUp(() {
    calls = [];
    reply = (_) async => null;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return reply(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  File file(String name) => File('/cache/downloads/$name');

  List<Map<Object?, Object?>> sentFiles() =>
      ((calls.single.arguments as Map<Object?, Object?>)['files']!
              as List<Object?>)
          .cast<Map<Object?, Object?>>();

  test('a RAW+JPEG pair is sent JPEG first, DNG second', () async {
    await PlatformMediaSaver().saveShot([
      file('R0001234.DNG'),
      file('R0001234.JPG'),
    ], album: 'GR Lab');

    expect(calls.single.method, 'saveShot');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['album'], 'GR Lab');
    expect(sentFiles(), [
      {
        'path': '/cache/downloads/R0001234.JPG',
        'name': 'R0001234.JPG',
        'kind': 'jpeg',
        'mimeType': 'image/jpeg',
      },
      {
        'path': '/cache/downloads/R0001234.DNG',
        'name': 'R0001234.DNG',
        'kind': 'dng',
        'mimeType': 'image/x-adobe-dng',
      },
    ]);
  });

  test('single files carry their kind and MIME type', () async {
    final saver = PlatformMediaSaver();
    await saver.saveShot([file('R0001235.jpeg')], album: 'GR Lab');
    await saver.saveShot([file('R0001236.dng')], album: 'GR Lab');
    await saver.saveShot([file('R0001237.MOV')], album: 'GR Lab');

    expect(
      [
        for (final c in calls)
          for (final f
              in ((c.arguments as Map<Object?, Object?>)['files']!
                      as List<Object?>)
                  .cast<Map<Object?, Object?>>())
            (f['kind'], f['mimeType']),
      ],
      [
        ('jpeg', 'image/jpeg'),
        ('dng', 'image/x-adobe-dng'),
        ('movie', 'video/quicktime'),
      ],
    );
  });

  test('files that are not one shot are refused before the channel', () async {
    final saver = PlatformMediaSaver();
    for (final shot in [
      <File>[],
      [file('R0001234.JPG'), file('R0001235.JPG')],
      [file('R0001234.DNG'), file('R0001234.MOV')],
      [file('R0001234.JPG'), file('R0001234.DNG'), file('R0001234.MOV')],
      [file('R0001234.TIF')],
      [file('README')],
    ]) {
      await expectLater(
        saver.saveShot(shot, album: 'GR Lab'),
        throwsA(
          isA<MediaSaveException>().having(
            (e) => e.failure,
            'failure',
            MediaSaveFailure.unsupported,
          ),
        ),
        reason: shot.map((f) => f.path).join(', '),
      );
    }
    expect(calls, isEmpty);
  });

  test('a native permission denial maps to permissionDenied', () async {
    reply = (_) async => throw PlatformException(
      code: 'permissionDenied',
      message: 'GR Lab may not add to Photos',
    );
    await expectLater(
      PlatformMediaSaver().saveShot([file('R0001234.JPG')], album: 'GR Lab'),
      throwsA(
        isA<MediaSaveException>()
            .having((e) => e.permissionDenied, 'permissionDenied', isTrue)
            .having(
              (e) => e.detail,
              'detail',
              'permissionDenied: GR Lab may not add to Photos',
            ),
      ),
    );
  });

  test('unknown native errors map to failed', () async {
    reply = (_) async => throw PlatformException(code: 'IOException');
    await expectLater(
      PlatformMediaSaver().saveShot([file('R0001234.JPG')], album: 'GR Lab'),
      throwsA(
        isA<MediaSaveException>()
            .having((e) => e.failure, 'failure', MediaSaveFailure.failed)
            .having((e) => e.permissionDenied, 'permissionDenied', isFalse),
      ),
    );
  });

  test('a missing native side is reported as unsupported', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      PlatformMediaSaver().saveShot([file('R0001234.JPG')], album: 'GR Lab'),
      throwsA(
        isA<MediaSaveException>().having(
          (e) => e.failure,
          'failure',
          MediaSaveFailure.unsupported,
        ),
      ),
    );
  });
}
