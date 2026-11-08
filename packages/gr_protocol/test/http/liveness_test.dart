import 'dart:io';

import 'package:gr_protocol/src/http/http.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 7, 12);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  group('LivenessTracker (Image Sync rule)', () {
    test('three failures within 40 s are not a loss', () {
      final t = LivenessTracker(start: t0);
      expect(t.recordFailure(at(1)), isFalse);
      expect(t.recordFailure(at(2)), isFalse);
      expect(t.recordFailure(at(39)), isFalse);
      expect(t.consecutiveFailures, 3);
      expect(t.lost, isFalse);
    });

    test('40 s without success but only two failures is not a loss', () {
      final t = LivenessTracker(start: t0);
      expect(t.recordFailure(at(40)), isFalse);
      expect(t.recordFailure(at(60)), isFalse);
    });

    test('third consecutive failure at ≥ 40 s declares the loss once', () {
      final t = LivenessTracker(start: t0);
      t.recordFailure(at(1));
      t.recordFailure(at(2));
      expect(t.recordFailure(at(40)), isTrue);
      expect(t.lost, isTrue);
      expect(t.recordFailure(at(41)), isFalse);
    });

    test('a success resets the count and the 40 s window', () {
      final t = LivenessTracker(start: t0);
      t.recordFailure(at(1));
      t.recordFailure(at(2));
      t.recordSuccess(at(30));
      expect(t.consecutiveFailures, 0);
      t.recordFailure(at(50));
      t.recordFailure(at(60));
      expect(t.recordFailure(at(69)), isFalse, reason: '39 s since success');
      expect(t.recordFailure(at(70)), isTrue);
    });

    test('thresholds are configurable', () {
      final t = LivenessTracker(
        start: t0,
        failureThreshold: 1,
        lossAfter: const Duration(seconds: 5),
      );
      expect(t.recordFailure(at(4)), isFalse);
      expect(t.recordFailure(at(5)), isTrue);
      expect(
        () => LivenessTracker(start: t0, failureThreshold: 0),
        throwsArgumentError,
      );
    });
  });

  group('LivenessMonitor', () {
    GrProps props(String serial) => GrProps({
      'errCode': 200,
      'model': 'RICOH GR IV HDF',
      'serialNo': serial,
      'bdName': 'GR_1',
    });

    test(
      'identity change counts as failure; loss uses the injected clock',
      () async {
        var now = t0;
        final answers = <Object>[
          props('A'),
          props('B'),
          const SocketException('unreachable'),
          props('B'),
        ];
        var i = 0;
        final monitor = LivenessMonitor.withProbe(() async {
          final a = answers[i++];
          if (a is GrProps) return a;
          throw a;
        }, clock: () => now);
        addTearDown(monitor.stop);

        now = at(1);
        final first = await monitor.pollOnce();
        expect(first.ok, isTrue);
        expect(monitor.identity!.serialNo, 'A');

        now = at(10);
        final mismatch = await monitor.pollOnce();
        expect((mismatch.ok, mismatch.identityMismatch), (false, true));

        now = at(20);
        final error = await monitor.pollOnce();
        expect(error.error, isA<SocketException>());
        expect(error.lost, isFalse);

        now = at(41);
        final last = await monitor.pollOnce();
        expect(last.consecutiveFailures, 3);
        expect(last.sinceLastSuccess, const Duration(seconds: 40));
        expect(last.lost, isTrue);
        expect(await monitor.lost, same(last));
      },
    );
  });
}
