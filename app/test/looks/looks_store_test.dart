import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/looks/looks_store.dart';

void main() {
  late Directory dataDir;
  final data = Uint8List.fromList(FakeLook.presets[0].data);

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
