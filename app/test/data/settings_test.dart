import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/theme/tokens.dart';

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
      ..theme = AppTheme.dark
      ..connectWhenNearby = false
      ..shootMode = ShootMode.liveView;
    await expectLater(settings.flush(), throwsA(isA<FileSystemException>()));
    expect(printed, contains(startsWith('Saving settings.json failed')));

    await blocker.delete();
    settings.autoDisconnect = AutoDisconnect.never;
    await settings.flush();

    final reloaded = await SettingsController.load(temp);
    expect(reloaded.theme, AppTheme.dark);
    expect(reloaded.shootMode, ShootMode.liveView);
    expect(reloaded.connectWhenNearby, isFalse);
    expect(reloaded.autoDisconnect, AutoDisconnect.never);
    // Failed writes leave no temporary files behind.
    expect(temp.listSync().map((e) => e.uri.pathSegments.last), [
      'settings.json',
    ]);
  });

  test('the language is saved with its script, and a saved language GR Lab '
      'is not translated into follows the phone', () async {
    const traditionalChinese = Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    );
    final settings = await SettingsController.load(temp);
    expect(settings.language, isNull);
    settings.language = traditionalChinese;
    await settings.flush();
    expect((await SettingsController.load(temp)).language, traditionalChinese);

    await File('${temp.path}/settings.json').writeAsString('{"language":"nb"}');
    expect((await SettingsController.load(temp)).language, isNull);
  });
}
