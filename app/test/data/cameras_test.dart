import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/data/cameras.dart';

SavedCamera _camera(String serial) => SavedCamera(
  paired: GrPairedCamera(
    deviceId: 'device-1',
    serialNumber: serial,
    modelName: 'RICOH GR IV',
    firmwareRevision: '1.10',
    bluetoothDeviceName: 'GR_000001',
  ),
  name: 'GR IV',
  pairedAt: DateTime.utc(2026, 11, 7, 9, 41),
);

void main() {
  late Directory temp;
  late List<String> printed;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cameras_test');
    printed = [];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);
  });

  tearDown(() => temp.delete(recursive: true));

  test('a failed write fails its change and is reported; later changes are '
      'saved with the one it lost', () async {
    final store = await CameraStore.load(temp);
    await store.add(_camera('1234567'));
    // A folder where cameras.json goes: the write cannot replace it.
    final file = File('${temp.path}/cameras.json');
    await file.delete();
    final blocker = await Directory(file.path).create();
    final added = store.add(_camera('7654321'));
    final selected = store.select('1234567');
    await expectLater(added, throwsA(isA<FileSystemException>()));
    await expectLater(selected, throwsA(isA<FileSystemException>()));
    expect(printed, contains(startsWith('Saving cameras.json failed')));

    await blocker.delete();
    await store.rename('7654321', 'Street');

    final reloaded = await CameraStore.load(temp);
    expect(
      [for (final c in reloaded.cameras) (c.serial, c.name)],
      [('1234567', 'GR IV'), ('7654321', 'Street')],
    );
    expect(temp.listSync().map((e) => e.uri.pathSegments.last), [
      'cameras.json',
    ]);
  });
}
