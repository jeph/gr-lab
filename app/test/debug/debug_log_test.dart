import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/debug/debug_log.dart';

void main() {
  late Directory temp;
  late Directory logDir;
  late SettingsController settings;
  final shared = <List<File>>[];
  Completer<void>? shareGate;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('debug_log_test');
    logDir = Directory('${temp.path}/debug-log');
    settings = await SettingsController.load(temp);
    shared.clear();
    shareGate = null;
  });

  tearDown(() => temp.delete(recursive: true));

  Future<DebugLog> open({
    bool defaultEnabled = true,
    int maxFileBytes = 1 << 20,
    int maxFiles = 10,
  }) => DebugLog.open(
    dir: logDir,
    defaultEnabled: defaultEnabled,
    settings: settings,
    maxFileBytes: maxFileBytes,
    maxFiles: maxFiles,
    share: (files, origin) async {
      shared.add(files);
      await shareGate?.future;
    },
  );

  // Same-length events, so file sizes are exact multiples of one line.
  TraceEvent event(int i) => TraceEvent(
    channel: TraceChannel.ble,
    direction: TraceDirection.inbound,
    kind: 'e${i.toString().padLeft(2, '0')}',
    time: DateTime.utc(2026, 11, 8),
  );

  final lineBytes = utf8.encode('${jsonEncode(event(0).toJson())}\n').length;

  List<String> kinds(String text) => [
    for (final line in const LineSplitter().convert(text))
      (jsonDecode(line) as Map<String, Object?>)['kind']! as String,
  ];

  Future<List<String>> names() async =>
      [for (final f in await logDir.list().toList()) f.uri.pathSegments.last]
        ..sort();

  test('on by default in dev and unflavored builds, off in prod', () {
    expect(DebugLog.defaultEnabledFor('dev'), isTrue);
    expect(DebugLog.defaultEnabledFor(null), isTrue);
    expect(DebugLog.defaultEnabledFor('prod'), isFalse);
  });

  test("the user's choice persists and overrides the default", () async {
    final log = await open(defaultEnabled: false);
    expect(log.enabled, isFalse);
    log.enabled = true;
    await settings.flush();

    settings = await SettingsController.load(temp);
    expect(settings.debugLogging, isTrue);
    expect((await open(defaultEnabled: false)).enabled, isTrue);

    final again = await open();
    again.enabled = false;
    await settings.flush();
    settings = await SettingsController.load(temp);
    expect((await open()).enabled, isFalse);
  });

  test('follows the setting wherever it changes, and says so', () async {
    final log = await open(defaultEnabled: false);
    var notified = 0;
    log.addListener(() => notified++);

    settings.debugLogging = true;
    expect((log.enabled, notified), (true, 1));
    settings.debugLogging = false;
    expect((log.enabled, notified), (false, 2));
    // Cleared, the build's default applies again.
    settings.debugLogging = null;
    expect((log.enabled, notified), (false, 3));
    log.dispose();
    settings.debugLogging = true;
    expect(notified, 3);

    // Recording follows the setting too.
    final reopened = await open(defaultEnabled: false)
      ..sink(event(0));
    settings.debugLogging = false;
    reopened.sink(event(1));
    await reopened.flush();
    await settings.flush();
    expect(reopened.sizeBytes, lineBytes);
  });

  test('records nothing while off', () async {
    final log = await open(defaultEnabled: false);
    log
      ..sink(event(0))
      ..recordPrint('hello')
      ..onUncaughtError(StateError('boom'), StackTrace.current);
    await log.flush();
    expect(await names(), isEmpty);
    expect(log.sizeBytes, 0);
  });

  test('app prints and uncaught errors land beside camera traffic', () async {
    final log = await open();
    log
      ..sink(event(0))
      ..recordPrint('hello');
    // False lets the engine still report the error as unhandled.
    expect(
      log.onUncaughtError(StateError('boom'), StackTrace.current),
      isFalse,
    );
    await log.flush();

    final lines = [
      for (final l in await File(
        '${logDir.path}/trace-000001.jsonl',
      ).readAsLines())
        jsonDecode(l) as Map<String, Object?>,
    ];
    expect(
      [for (final l in lines) (l['channel'], l['kind'])],
      [('ble', 'e00'), ('app', 'print'), ('app', 'error')],
    );
    expect((lines[1]['fields']! as Map)['message'], 'hello');
    final error = lines[2]['fields']! as Map;
    expect(error['error'], contains('boom'));
    expect(error['stack'], contains('debug_log_test.dart'));
  });

  test('runWithDebugLog: console before the log opens, then log and console '
      'while on, nowhere while off', () async {
    final console = <String>[];
    DebugLog? current;
    void say(String line) => runZoned(
      () => runWithDebugLog(() => current, () => Zone.current.print(line)),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => console.add(line),
      ),
    );

    say('starting');
    current = await open();
    say('on');
    current.enabled = false;
    say('off');
    current.enabled = true;
    await current.flush();
    await settings.flush();

    expect(console, ['starting', 'on']);
    final logged = [
      for (final l in await File(
        '${logDir.path}/trace-000001.jsonl',
      ).readAsLines())
        ((jsonDecode(l) as Map)['fields'] as Map)['message'],
    ];
    expect(logged, ['on']);
  });

  test('records events as JSON Lines and appends across restarts', () async {
    final log = await open();
    log.sink(event(0));
    log.sink(event(1));
    await log.close();

    final reopened = await open();
    expect(reopened.sizeBytes, 2 * lineBytes);
    reopened.sink(event(2));
    await reopened.flush();
    expect(await names(), ['trace-000001.jsonl']);
    final text = await File('${logDir.path}/trace-000001.jsonl').readAsString();
    expect(kinds(text), ['e00', 'e01', 'e02']);
    expect(reopened.sizeBytes, 3 * lineBytes);
  });

  test('a record left half-written by a crash is cut off, so the next one '
      'starts its own line', () async {
    final log = await open();
    log.sink(event(0));
    await log.close();
    final file = File('${logDir.path}/trace-000001.jsonl');
    final torn = jsonEncode(event(1).toJson()).substring(0, 20);
    await file.writeAsString(torn, mode: FileMode.append);

    final reopened = await open();
    reopened.sink(event(2));
    await reopened.flush();
    expect(kinds(await file.readAsString()), ['e00', 'e02']);
    expect(reopened.sizeBytes, 2 * lineBytes);
  });

  test('a half-written record is cut off even when the next one starts a '
      'new file', () async {
    // Two lines fill a file: the next record goes to a new one.
    final log = await open(maxFileBytes: 2 * lineBytes);
    log
      ..sink(event(0))
      ..sink(event(1));
    await log.close();
    final torn = jsonEncode(event(2).toJson()).substring(0, 20);
    await File('${logDir.path}/trace-000001.jsonl')
        .writeAsString(torn, mode: FileMode.append);

    final reopened = await open(maxFileBytes: 2 * lineBytes);
    reopened.sink(event(3));
    expect(await reopened.export(), isTrue);
    expect(
      [for (final f in shared.single) kinds(await f.readAsString())],
      [
        ['e00', 'e01'],
        ['e03'],
      ],
    );
    expect(reopened.sizeBytes, 3 * lineBytes);
  });

  for (final enabled in [true, false]) {
    test('a log folder that cannot be opened leaves the log unavailable, '
        'not failing (logging ${enabled ? 'on' : 'off'})', () async {
      // A file where the folder goes.
      await File(logDir.path).writeAsString('');
      final log = await open(defaultEnabled: enabled);
      expect(log.available, isFalse);
      expect(log.enabled, enabled);
      log.sink(event(0));
      await log.flush();
      expect(log.sizeBytes, 0);
      expect(await log.export(), isFalse);
      expect(shared, isEmpty);
      await log.close();
    });
  }

  test('rotation keeps the newest data and drops the oldest file', () async {
    // Two lines fill a file exactly; the third starts the next one.
    final log = await open(maxFileBytes: 2 * lineBytes, maxFiles: 2);
    for (var i = 0; i < 5; i++) {
      log.sink(event(i));
    }
    await log.flush();

    expect(await names(), ['trace-000002.jsonl', 'trace-000003.jsonl']);
    final second = await File('${logDir.path}/trace-000002.jsonl')
        .readAsString();
    final third = await File('${logDir.path}/trace-000003.jsonl')
        .readAsString();
    expect(kinds(second), ['e02', 'e03']);
    expect(kinds(third), ['e04']);
    expect(log.sizeBytes, 3 * lineBytes);
  });

  test(
    'export flushes pending writes and shares every file in order',
    () async {
      final log = await open(maxFileBytes: 2 * lineBytes);
      for (var i = 0; i < 5; i++) {
        log.sink(event(i));
      }
      // No flush: export must wait for the queued writes itself.
      expect(await log.export(), isTrue);

      expect(shared, hasLength(1));
      final files = shared.single;
      expect(
        [for (final f in files) f.uri.pathSegments.last],
        ['trace-000001.jsonl', 'trace-000002.jsonl', 'trace-000003.jsonl'],
      );
      final all = StringBuffer();
      for (final f in files) {
        all.write(await f.readAsString());
      }
      expect(kinds('$all'), ['e00', 'e01', 'e02', 'e03', 'e04']);
    },
  );

  test(
    'files handed to an open share sheet survive rotation and clear',
    () async {
      final log = await open(maxFileBytes: 2 * lineBytes, maxFiles: 2);
      for (var i = 0; i < 3; i++) {
        log.sink(event(i));
      }
      shareGate = Completer<void>();
      final exported = log.export();
      while (shared.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(shared, hasLength(1), reason: 'share sheet open');

      // Recording goes on: rotation drops trace-000001 and -000002 ...
      for (var i = 3; i < 9; i++) {
        log.sink(event(i));
      }
      await log.flush();
      expect(File('${logDir.path}/trace-000001.jsonl').existsSync(), isFalse);
      // ... and the user clears the log.
      await log.clear();

      final files = shared.single;
      expect(
        [for (final f in files) f.uri.pathSegments.last],
        ['trace-000001.jsonl', 'trace-000002.jsonl'],
      );
      final all = StringBuffer();
      for (final f in files) {
        all.write(await f.readAsString());
      }
      expect(kinds('$all'), ['e00', 'e01', 'e02']);

      shareGate!.complete();
      expect(await exported, isTrue);
      // The next export replaces the old copies.
      log.sink(event(9));
      shareGate = null;
      expect(await log.export(), isTrue);
      expect(files.first.existsSync(), isFalse);
      expect(kinds(await shared.last.single.readAsString()), ['e09']);
    },
  );

  test('export of an empty log shares nothing', () async {
    final log = await open();
    expect(await log.export(), isFalse);
    expect(shared, isEmpty);
  });

  test('clear removes every file and starts over', () async {
    final log = await open(maxFileBytes: 2 * lineBytes);
    for (var i = 0; i < 5; i++) {
      log.sink(event(i));
    }
    await log.flush();
    expect(await names(), hasLength(3));
    await log.clear();
    expect(await names(), isEmpty);
    expect(log.sizeBytes, 0);
    expect(await log.export(), isFalse);

    log.sink(event(9));
    await log.flush();
    expect(await names(), ['trace-000001.jsonl']);
    expect(log.sizeBytes, lineBytes);
  });
}
