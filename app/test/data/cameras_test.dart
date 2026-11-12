import 'dart:convert';
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

  test('geotagging choices are saved with the camera and load again', () async {
    final store = await CameraStore.load(temp);
    await store.add(_camera('1234567'));
    expect(store.current!.liveGeotagging, isFalse);
    expect(store.current!.backgroundGeotagging, isFalse);
    expect(store.current!.syncClock, isTrue);
    expect(store.current!.keepsClock, isTrue);
    expect(store.current!.storeLocationInfoPending, isNull);

    await store.setLiveGeotagging('1234567', on: true);
    await store.setSyncClock('1234567', on: false);
    var reloaded = (await CameraStore.load(temp)).current!;
    expect(reloaded.liveGeotagging, isTrue);
    expect(reloaded.backgroundGeotagging, isFalse);
    expect(reloaded.syncClock, isFalse);
    // Live geotagging does not keep the clock by itself.
    expect(reloaded.keepsClock, isFalse);
    expect(reloaded.storeLocationInfoPending, isTrue);

    // The camera took another value than the one it is owed now.
    await store.storeLocationInfoWritten('1234567', written: false);
    expect(store.current!.storeLocationInfoPending, isTrue);
    await store.storeLocationInfoWritten('1234567', written: true);
    expect(store.current!.storeLocationInfoPending, isNull);

    await store.setLiveGeotagging('1234567', on: false);
    reloaded = (await CameraStore.load(temp)).current!;
    expect(reloaded.liveGeotagging, isFalse);
    expect(reloaded.storeLocationInfoPending, isFalse);
  });

  test('background geotagging is saved for each camera, and keeps that '
      "camera's clock in sync whatever its clock switch says", () async {
    final store = await CameraStore.load(temp);
    await store.add(_camera('1234567'));
    await store.add(_camera('7654321'));
    await store.setSyncClock('1234567', on: false);
    await store.setSyncClock('7654321', on: false);
    await store.setBackgroundGeotagging('1234567', on: true);

    var reloaded = (await CameraStore.load(temp)).cameras;
    SavedCamera of(String serial) =>
        reloaded.singleWhere((camera) => camera.serial == serial);
    expect(of('1234567').backgroundGeotagging, isTrue);
    expect(of('1234567').syncClock, isFalse);
    expect(of('1234567').keepsClock, isTrue);
    expect(of('1234567').liveGeotagging, isFalse);
    expect(of('1234567').storeLocationInfoPending, isNull);
    expect(of('7654321').backgroundGeotagging, isFalse);
    expect(of('7654321').keepsClock, isFalse);

    await store.setBackgroundGeotagging('1234567', on: false);
    reloaded = (await CameraStore.load(temp)).cameras;
    expect(of('1234567').backgroundGeotagging, isFalse);
    // The user's own choice is what is left.
    expect(of('1234567').keepsClock, isFalse);
  });

  test('a camera saved before GR Photo had geotagging loads with both '
      'kinds of geotagging off and its clock kept in sync', () async {
    final store = await CameraStore.load(temp);
    await store.add(_camera('1234567'));
    final file = File('${temp.path}/cameras.json');
    final saved = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final entry = (saved['cameras']! as List<Object?>).single;
    expect(
      (entry! as Map<String, Object?>).keys,
      unorderedEquals(['paired', 'name', 'pairedAt']),
    );

    final loaded = (await CameraStore.load(temp)).current!;
    expect(loaded.serial, '1234567');
    expect(loaded.liveGeotagging, isFalse);
    expect(loaded.backgroundGeotagging, isFalse);
    expect(loaded.syncClock, isTrue);
    expect(loaded.storeLocationInfoPending, isNull);
  });
}
