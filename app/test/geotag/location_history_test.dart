import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/geotag/location_history.dart';

import 'photo_files.dart' show namesIn;

/// Midday of the day the tests start on.
final _noon = DateTime.utc(2026, 11, 12, 12);

const _minute = Duration(minutes: 1);
const _day = Duration(days: 1);

/// A made-up position taken at [time]; tests tell positions apart by
/// their [latitude].
LocationFix _at(
  DateTime time, {
  double latitude = 35,
  double accuracy = 10,
  double? altitude,
}) => LocationFix(
  latitude: latitude,
  longitude: 139,
  accuracy: accuracy,
  altitude: altitude,
  time: time,
);

/// The name of the file that holds the UTC day of [time].
String _dayFile(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => '$value'.padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)}.txt';
}

void main() {
  late Directory temp;
  late Directory dir;

  // What the phone's clock says; a test moves it.
  late DateTime now;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('location_history_test');
    dir = Directory('${temp.path}/location-history');
    now = _noon.add(const Duration(hours: 1));
  });

  tearDown(() => temp.delete(recursive: true));

  // A test whose body sees `now` as the time.
  void historyTest(String description, Future<void> Function() body) =>
      test(description, () => withClock(Clock(() => now), body));

  List<String> lines(DateTime day) =>
      File('${dir.path}/${_dayFile(day)}').readAsLinesSync();

  historyTest('a new history is an empty directory', () async {
    final history = await LocationHistory.open(dir);
    expect(dir.existsSync(), isTrue);
    expect(namesIn(dir), isEmpty);
    expect(await history.isEmpty, isTrue);
    expect(await history.nearest(_noon), isNull);
  });

  historyTest('nearest is the position nearest in time, before or '
      'after', () async {
    final history = await LocationHistory.open(dir);
    await history.add([
      _at(_noon.subtract(_minute * 10), latitude: 1),
      _at(_noon.add(_minute * 4), latitude: 2),
    ]);
    expect(await history.isEmpty, isFalse);

    Future<double?> nearest(DateTime capturedAt) async =>
        (await history.nearest(capturedAt))?.latitude;

    expect(await nearest(_noon), 2);
    expect(await nearest(_noon.subtract(_minute * 4)), 1);
    expect(await nearest(_noon.subtract(_minute * 10)), 1);
    // As far from both: the earlier one.
    expect(await nearest(_noon.subtract(_minute * 3)), 1);
    expect(await nearest(_noon.add(_minute * 4)), 2);
    // However long after the last position.
    expect(await nearest(_noon.add(_minute * 59)), 2);
    // The same instant given in the phone's zone.
    expect(await nearest(_noon.toLocal()), 2);
  });

  historyTest('positions are matched by their own time, not by when they '
      'arrived', () async {
    final history = await LocationHistory.open(dir);
    await history.add([_at(_noon.add(_minute * 2), latitude: 3)]);
    await history.add([_at(_noon.subtract(_minute * 20), latitude: 1)]);
    await history.add([_at(_noon.subtract(_minute), latitude: 2)]);

    expect((await history.nearest(_noon))?.latitude, 2);
    expect((await history.nearest(_noon.subtract(_minute * 15)))?.latitude, 1);
    expect((await history.nearest(_noon.add(_minute)))?.latitude, 3);
    // The file itself is only ever appended to.
    expect(
      [for (final line in lines(_noon)) line.split(',')[1]],
      ['3.0', '1.0', '2.0'],
    );
  });

  historyTest('a photo with no position before it takes the next one only '
      'within 10 minutes', () async {
    final history = await LocationHistory.open(dir);
    final first = _noon.add(_minute * 10);
    await history.add([_at(first)]);

    expect((await history.nearest(_noon))?.time, first);
    expect(
      await history.nearest(_noon.subtract(const Duration(seconds: 1))),
      isNull,
    );
    expect(await history.nearest(_noon.subtract(_day)), isNull);
  });

  historyTest('the position before or after can be in another day', () async {
    final history = await LocationHistory.open(dir);
    final midnight = DateTime.utc(2026, 11, 12);
    await history.add([
      _at(midnight.subtract(_day * 5).add(_minute), latitude: 1),
      _at(midnight.add(_minute * 5), latitude: 2),
    ]);
    expect(namesIn(dir), ['2026-11-07.txt', '2026-11-12.txt']);

    Future<double?> nearest(DateTime capturedAt) async =>
        (await history.nearest(capturedAt))?.latitude;

    // Two minutes before midnight: the next day's is seven minutes away.
    expect(await nearest(midnight.subtract(_minute * 2)), 2);
    // Four days after the first, one day before the second.
    expect(await nearest(midnight.subtract(_day)), 2);
    // One day after the first, four days before the second.
    expect(await nearest(midnight.subtract(_day * 4)), 1);
    // A minute before the first.
    expect(await nearest(midnight.subtract(_day * 5)), 1);
    // A day before the first.
    expect(await nearest(midnight.subtract(_day * 6)), isNull);
  });

  historyTest('a photo taken more than 90 days ago gets none', () async {
    final history = await LocationHistory.open(dir);
    await history.add([_at(_noon)]);
    expect(await history.nearest(_noon), isNotNull);

    now = _noon.add(_day * 90).subtract(_minute);
    expect(await history.nearest(_noon), isNotNull);
    now = _noon.add(_day * 90).add(_minute);
    expect(await history.nearest(_noon), isNull);
  });

  historyTest('a position older than 90 days in a day still on disk is '
      'passed over', () async {
    final history = await LocationHistory.open(dir);
    await history.add([_at(_noon)]);

    // The position is 90 days and an hour old; its day has not ended 90
    // days ago yet, so its file is still there.
    now = _noon.add(_day * 90).add(const Duration(hours: 1));
    await history.add(const []);
    expect(namesIn(dir), [_dayFile(_noon)]);
    expect(await history.nearest(_noon.add(_minute * 90)), isNull);
    expect(await history.isEmpty, isTrue);
  });

  historyTest('adding deletes the days that ended more than 90 days '
      'ago', () async {
    final history = await LocationHistory.open(dir);
    await history.add([_at(_noon), _at(_noon.add(_day))]);
    expect(namesIn(dir), ['2026-11-12.txt', '2026-11-13.txt']);

    now = _noon.add(_day * 91);
    await history.add([_at(now)]);
    expect(namesIn(dir), ['2026-11-13.txt', _dayFile(now)]);
    expect(namesIn(dir).last, '2027-02-11.txt');
  });

  historyTest('opening deletes the days that ended more than 90 days '
      'ago', () async {
    final history = await LocationHistory.open(dir);
    await history.add([_at(_noon), _at(_noon.add(_day))]);
    await File('${dir.path}/notes.txt').writeAsString('not a day');

    now = _noon.add(_day * 91).add(_minute);
    final reopened = await LocationHistory.open(dir);
    expect(namesIn(dir), ['2026-11-13.txt', 'notes.txt']);
    // The position left is 90 days and a minute old by now.
    expect(await reopened.isEmpty, isTrue);
  });

  historyTest('the time kept can be chosen', () async {
    final history = await LocationHistory.open(dir, keep: _day * 2);
    await history.add([
      _at(now.subtract(_day * 3), latitude: 1),
      _at(now.subtract(_day), latitude: 2),
    ]);
    expect(namesIn(dir), [_dayFile(now.subtract(_day))]);
    expect(await history.nearest(now.subtract(_day * 3)), isNull);
    expect((await history.nearest(now))?.latitude, 2);
  });

  historyTest('a position older than 90 days is not added', () async {
    final history = await LocationHistory.open(dir);
    await history.add([
      _at(now.subtract(_day * 90).subtract(_minute), latitude: 1),
      _at(now.subtract(_day * 89), latitude: 2),
    ]);
    expect(namesIn(dir), [_dayFile(now.subtract(_day * 89))]);
    expect(lines(now.subtract(_day * 89)), hasLength(1));
  });

  historyTest('a position that repeats the one added last is left '
      'out', () async {
    final history = await LocationHistory.open(dir);
    final first = _at(_noon, latitude: 1, altitude: 20);
    final second = _at(_noon.add(_minute), latitude: 2);
    await history.add([first, first]);
    await history.add([first]);
    expect(lines(_noon), hasLength(1));

    // Not the last one any more, so it counts as new.
    await history.add([second, first]);
    expect(lines(_noon), hasLength(3));

    final reopened = await LocationHistory.open(dir);
    await reopened.add([first]);
    expect(lines(_noon), hasLength(3));
    // Another accuracy is another position.
    await reopened.add([_at(_noon, latitude: 1, altitude: 20, accuracy: 5)]);
    expect(lines(_noon), hasLength(4));
  });

  historyTest('a day is one text file of its UTC day, a line per '
      'position', () async {
    final history = await LocationHistory.open(dir);
    final lastOfDay = DateTime.utc(2026, 11, 11, 23, 59, 59, 999);
    final firstOfDay = DateTime.utc(2026, 11, 12);
    await history.add([
      LocationFix(
        latitude: 35.5,
        longitude: -139.25,
        accuracy: 12.5,
        altitude: 40,
        time: lastOfDay,
      ),
      LocationFix(
        latitude: -35.5,
        longitude: 139.25,
        accuracy: double.infinity,
        time: firstOfDay.toLocal(),
      ),
    ]);

    expect(namesIn(dir), ['2026-11-11.txt', '2026-11-12.txt']);
    expect(
      File('${dir.path}/2026-11-11.txt').readAsStringSync(),
      '${lastOfDay.millisecondsSinceEpoch},35.5,-139.25,12.5,40.0\n',
    );
    expect(
      File('${dir.path}/2026-11-12.txt').readAsStringSync(),
      '${firstOfDay.millisecondsSinceEpoch},-35.5,139.25,,\n',
    );

    final reopened = await LocationHistory.open(dir);
    final evening = (await reopened.nearest(lastOfDay))!;
    expect(evening.time, lastOfDay);
    expect(evening.time.isUtc, isTrue);
    expect(evening.latitude, 35.5);
    expect(evening.longitude, -139.25);
    expect(evening.accuracy, 12.5);
    expect(evening.altitude, 40);
    final morning = (await reopened.nearest(firstOfDay.add(_minute)))!;
    expect(morning.time, firstOfDay);
    expect(morning.latitude, -35.5);
    expect(morning.accuracy, double.infinity);
    expect(morning.altitude, isNull);
  });

  historyTest('a position that is no place on Earth is not added', () async {
    final history = await LocationHistory.open(dir);
    await history.add([
      _at(_noon, latitude: 90.5),
      _at(_noon, latitude: double.nan),
    ]);
    expect(namesIn(dir), isEmpty);
    expect(await history.isEmpty, isTrue);
  });

  historyTest('clear deletes every day and nothing else', () async {
    final history = await LocationHistory.open(dir);
    final last = _at(_noon);
    await history.add([_at(_noon.subtract(_day)), last]);
    await File('${dir.path}/notes.txt').writeAsString('not a day');
    expect(await history.nearest(_noon), isNotNull);

    await history.clear();
    expect(namesIn(dir), ['notes.txt']);
    expect(await history.isEmpty, isTrue);
    expect(await history.nearest(_noon), isNull);

    // The history goes on afterwards, and remembers no last position.
    await history.add([last]);
    expect(namesIn(dir), [_dayFile(_noon), 'notes.txt']);
    expect((await history.nearest(_noon))?.time, _noon);
    expect(await (await LocationHistory.open(dir)).isEmpty, isFalse);
  });

  historyTest('a malformed line is skipped, and a line cut short neither '
      'counts nor swallows the next position', () async {
    int at(int minutesBefore) =>
        _noon.subtract(_minute * minutesBefore).millisecondsSinceEpoch;
    final file = File('${dir.path}/${_dayFile(_noon)}');
    await dir.create(recursive: true);
    await file.writeAsBytes([
      ...'garbage\n'.codeUnits,
      0xFF, 0xFE, 0x0A, //
      ...'\n'.codeUnits,
      ...'${at(30)},1.0,139.0,10.0,\n'.codeUnits,
      // Not on Earth, too few values, another day's time, no time, no
      // number, too many values.
      ...'${at(20)},95.0,139.0,10.0,\n'.codeUnits,
      ...'${at(10)},2.0,139.0\n'.codeUnits,
      ...'${at(8 + 2 * 24 * 60)},3.0,139.0,10.0,\n'.codeUnits,
      ...'soon,4.0,139.0,10.0,\n'.codeUnits,
      ...'${at(5)},5.0,139.0,x,\n'.codeUnits,
      ...'${at(4)},6.0,139.0,10.0,7.0,8.0\n'.codeUnits,
      // Cut short while it was written: it has no line end.
      ...'${at(1)},7.0,139.0,10.0,7'.codeUnits,
    ]);

    final history = await LocationHistory.open(dir);
    expect(await history.isEmpty, isFalse);
    expect((await history.nearest(_noon))?.latitude, 1);

    // The line cut short reads as a whole position once a line end
    // follows it, with 7 for whatever its altitude was; it is closed so
    // that it never does.
    await history.add([_at(_noon.subtract(_minute * 2), latitude: 9)]);
    expect((await history.nearest(_noon))?.latitude, 9);
    expect(
      String.fromCharCodes(file.readAsBytesSync()),
      endsWith('${at(1)},7.0,139.0,10.0,7#\n${at(2)},9.0,139.0,10.0,\n'),
    );
    final reopened = await LocationHistory.open(dir);
    expect((await reopened.nearest(_noon))?.latitude, 9);
    // And nothing was rewritten.
    expect(String.fromCharCodes(file.readAsBytesSync()), startsWith('garbage'));
  });

  historyTest('a day with only malformed lines counts as empty', () async {
    await dir.create(recursive: true);
    await File('${dir.path}/${_dayFile(_noon)}').writeAsString('garbage\n');
    final history = await LocationHistory.open(dir);
    expect(await history.isEmpty, isTrue);
    expect(await history.nearest(_noon), isNull);
  });

  historyTest('calls made at once run one after the other', () async {
    final history = await LocationHistory.open(dir);
    final adds = <Future<void>>[];
    final found = <Future<LocationFix?>>[];
    for (var i = 0; i < 40; i++) {
      final time = _noon.add(Duration(seconds: i));
      adds.add(history.add([_at(time, latitude: i.toDouble())]));
      found.add(history.nearest(_noon.add(_minute)));
    }
    await Future.wait(adds);

    expect(
      [for (final line in lines(_noon)) line.split(',')[1]],
      [for (var i = 0; i < 40; i++) '${i.toDouble()}'],
    );
    // Each answer is the position added just before it was asked for.
    expect(
      [for (final fix in await Future.wait(found)) fix?.latitude],
      [for (var i = 0; i < 40; i++) i.toDouble()],
    );

    // Each call sees what the calls made before it did.
    final results = await Future.wait<Object?>([
      history.add([_at(_noon.add(_minute * 2), latitude: 50)]),
      history.nearest(_noon.add(_minute * 2)),
      history.clear(),
      history.isEmpty,
      history.add([_at(_noon.add(_minute * 3), latitude: 60)]),
      history.nearest(_noon),
    ]);
    expect((results[1] as LocationFix?)?.latitude, 50);
    expect(results[3], isTrue);
    expect((results[5] as LocationFix?)?.latitude, 60);
    expect(lines(_noon), hasLength(1));
  });

  historyTest('a history that cannot be written loses the positions '
      'without failing', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);

    final history = await LocationHistory.open(dir);
    await dir.delete(recursive: true);
    await history.add([_at(_noon, latitude: 12.5)]);

    expect(await history.nearest(_noon), isNull);
    expect(await history.isEmpty, isTrue);
    await history.clear();
    expect(printed, [startsWith('Writing 2026-11-12.txt of the location')]);
    // The debug log names the file, never the position.
    expect(printed.single, isNot(contains('12.5')));
  });
}
