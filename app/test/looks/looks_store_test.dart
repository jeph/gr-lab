import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/looks/looks_store.dart';

void main() {
  late Directory dataDir;
  final data = Uint8List.fromList(FakeLook.presets[0].data);
  final otherData = Uint8List.fromList(FakeLook.presets[1].data);

  Matcher conflict(LookConflictKind kind, SavedLook other) => throwsA(
    isA<LookConflict>()
        .having((c) => c.kind, 'kind', kind)
        .having((c) => c.other.id, 'other', other.id),
  );

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('grlab_looks_');
  });
  tearDown(() => dataDir.delete(recursive: true));

  // `looks.json` written as a temporary file renamed over it: a non-empty
  // directory in its place makes every write fail until it is removed.
  Directory blockWrites() {
    final file = File('${dataDir.path}/looks.json');
    if (file.existsSync()) file.deleteSync();
    final dir = Directory(file.path)..createSync();
    File('${dir.path}/keep').writeAsStringSync('');
    return dir;
  }

  Future<List<String>> namesOnDisk() async {
    final store = await LooksStore.load(dataDir);
    return [for (final l in store.looks) l.name];
  }

  test('a look with the name, the settings or both of a saved look is not '
      'added, and the conflict names that look', () async {
    final store = await LooksStore.load(dataDir);
    final tokyo = await store.add(name: 'Tokyo Night', data: data);
    // The same settings in other bytes: the header is not part of them.
    final sameSettings = Uint8List.fromList(data)..[1] = data[1] + 1;

    await expectLater(
      store.add(name: 'Tokyo Night', data: sameSettings, photo: Uint8List(4)),
      conflict(LookConflictKind.nameAndSettings, tokyo),
    );
    await expectLater(
      store.add(name: 'Shinjuku', data: sameSettings),
      conflict(LookConflictKind.settings, tokyo),
    );
    await expectLater(
      store.add(name: 'Tokyo Night', data: otherData),
      conflict(LookConflictKind.name, tokyo),
    );
    expect(store.looks.single.id, tokyo.id);
    expect(await namesOnDisk(), ['Tokyo Night']);
    expect(Directory('${dataDir.path}/looks').existsSync(), isFalse);

    await store.add(name: 'Shinjuku', data: otherData);
    expect(await namesOnDisk(), ['Shinjuku', 'Tokyo Night']);
  });

  test('a look is not renamed or changed into another saved look, but is '
      'saved again as itself', () async {
    final store = await LooksStore.load(dataDir);
    final tokyo = await store.add(name: 'Tokyo Night', data: data);
    final daido = await store.add(name: 'Daido', data: otherData);

    await expectLater(
      store.update(daido.copyWith(name: 'Tokyo Night')),
      conflict(LookConflictKind.name, tokyo),
    );
    await expectLater(
      store.update(daido.copyWith(data: data)),
      conflict(LookConflictKind.settings, tokyo),
    );
    await expectLater(
      store.update(daido.copyWith(name: 'Tokyo Night', data: data)),
      conflict(LookConflictKind.nameAndSettings, tokyo),
    );
    expect(store.byId(daido.id)!.name, 'Daido');
    expect(store.byId(daido.id)!.data, otherData);

    await store.update(daido.copyWith(name: 'Moriyama'));
    await store.update(tokyo.copyWith(data: data));
    expect(await namesOnDisk(), ['Moriyama', 'Tokyo Night']);
  });

  test("a look with one saved look's settings and another's name is "
      'refused for its settings', () async {
    final store = await LooksStore.load(dataDir);
    final tokyo = await store.add(name: 'Tokyo Night', data: data);
    await store.add(name: 'Daido', data: otherData);

    await expectLater(
      store.add(name: 'Daido', data: data),
      conflict(LookConflictKind.settings, tokyo),
    );
  });

  test(
    'a failed write does not stop the next one from reaching disk',
    () async {
      final store = await LooksStore.load(dataDir);
      final look = await store.add(name: 'Tokyo Night', data: data);

      final block = blockWrites();
      await expectLater(
        store.update(look.copyWith(name: 'Failed')),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.looks.single.name, 'Tokyo Night', reason: 'rolled back');

      block.deleteSync(recursive: true);
      await store.update(look.copyWith(name: 'Retried'));
      expect(await namesOnDisk(), ['Retried']);
    },
  );

  test('two overlapping updates that both fail leave the stored '
      'version', () async {
    final store = await LooksStore.load(dataDir);
    final look = await store.add(name: 'Tokyo Night', data: data);

    blockWrites();
    final first = store.update(look.copyWith(name: 'First'));
    final second = store.update(look.copyWith(name: 'Second'));
    await expectLater(first, throwsA(isA<FileSystemException>()));
    await expectLater(second, throwsA(isA<FileSystemException>()));
    expect(store.looks.single.name, 'Tokyo Night');
  });

  test('a look that could not be added is taken out, and adding it again '
      'stores it once', () async {
    final store = await LooksStore.load(dataDir);
    final block = blockWrites();
    await expectLater(
      store.add(name: 'Daido', data: data, photo: Uint8List(4)),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.looks, isEmpty);
    expect(Directory('${dataDir.path}/looks').listSync(), isEmpty);

    block.deleteSync(recursive: true);
    final added = await store.add(name: 'Daido', data: data);
    expect(await namesOnDisk(), ['Daido']);
    expect(store.looks.single.id, added.id);
  });

  test("a look saved from a photo keeps the photo's own look through edits "
      'and restarts; a look without a photo, or saved before GR Lab kept '
      'it, has none', () async {
    final store = await LooksStore.load(dataDir);
    final fromPhoto = await store.add(
      name: 'Street',
      data: data,
      photo: Uint8List(4),
    );
    final made = await store.add(name: 'Made here', data: otherData);
    expect(fromPhoto.photoLook!.settings, fromPhoto.settings);
    expect(made.photoLook, isNull);

    final edited = Uint8List.fromList(FakeLook.presets[2].data);
    await store.update(fromPhoto.copyWith(data: edited));
    final reloaded = await LooksStore.load(dataDir);
    final street = reloaded.looks.singleWhere((l) => l.name == 'Street');
    expect(street.data, edited);
    expect(street.photoData, data, reason: 'the photo did not change');
    expect(
      reloaded.looks.singleWhere((l) => l.name == 'Made here').photoData,
      isNull,
    );

    final file = File('${dataDir.path}/looks.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    for (final look in json['looks']! as List<Object?>) {
      (look! as Map<String, Object?>).remove('photoData');
    }
    file.writeAsStringSync(jsonEncode(json));
    final older = await LooksStore.load(dataDir);
    expect(older.looks.map((l) => l.photoLook), [null, null]);
  });

  test('a delete that could not be written brings the look and its photo '
      'back', () async {
    final store = await LooksStore.load(dataDir);
    final look = await store.add(
      name: 'Soft Summer',
      data: data,
      photo: Uint8List(4),
    );

    final block = blockWrites();
    await expectLater(store.delete(look), throwsA(isA<FileSystemException>()));
    expect(store.looks.single.id, look.id);
    expect(store.photoOf(look), isNotNull);

    block.deleteSync(recursive: true);
    await store.delete(look);
    expect(await namesOnDisk(), isEmpty);
    expect(store.photoOf(look), isNull);
  });
}
