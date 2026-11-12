import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/data/json_file.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('json_file_test');
  });

  tearDown(() => temp.delete(recursive: true));

  test('two writers of one document never write into the same temporary '
      'file', () async {
    final file = File('${temp.path}/downloads.json');
    final writers = [JsonFile(file), JsonFile(file)];
    await Future.wait([
      for (var i = 0; i < 20; i++) writers[i % 2].write({'write': i}),
    ]);

    expect((await writers.first.read())?['write'], isA<int>());
    expect(temp.listSync().map((e) => e.uri.pathSegments.last), [
      'downloads.json',
    ]);
  });
}
