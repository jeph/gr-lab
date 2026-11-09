import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/data/settings.dart';

void main() {
  late Directory temp;
  late List<String> printed;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('settings_test');
    printed = [];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);
  });

  tearDown(() => temp.delete(recursive: true));

  test('a failed write is reported, and later changes are saved with the '
      'ones it lost', () async {
    final settings = await SettingsController.load(temp);
    // A folder where settings.json goes: the write cannot replace it.
    final blocker = await Directory('${temp.path}/settings.json').create();
    settings
      ..themeMode = ThemeMode.dark
      ..shootMode = ShootMode.liveView;
    await expectLater(settings.flush(), throwsA(isA<FileSystemException>()));
    expect(printed, contains(startsWith('Saving settings.json failed')));

    await blocker.delete();
    settings.autoDisconnect = AutoDisconnect.never;
    await settings.flush();

    final reloaded = await SettingsController.load(temp);
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.shootMode, ShootMode.liveView);
    expect(reloaded.autoDisconnect, AutoDisconnect.never);
    // Failed writes leave no temporary files behind.
    expect(temp.listSync().map((e) => e.uri.pathSegments.last), [
      'settings.json',
    ]);
  });
}
