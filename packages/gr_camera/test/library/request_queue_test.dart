import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';

void main() {
  group('RequestQueue', () {
    test('runs at most its concurrency, newest first', () async {
      final q = RequestQueue();
      var running = 0;
      var peak = 0;
      final order = <int>[];
      final gate = Completer<void>();
      Future<int> task(int i) async {
        running++;
        peak = running > peak ? running : peak;
        order.add(i);
        await gate.future;
        running--;
        return i;
      }

      final requests = [for (var i = 0; i < 6; i++) q.add(() => task(i))];
      await Future<void>.delayed(Duration.zero);
      expect(q.running, 3);
      expect(order, [0, 1, 2]);
      gate.complete();
      expect(await Future.wait([for (final r in requests) r.future]), [
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(peak, 3);
      expect(order.sublist(3), [5, 4, 3]);
    });

    test('a request cancelled before it starts never runs', () async {
      final q = RequestQueue(concurrency: 1);
      final gate = Completer<void>();
      var ran = false;
      final first = q.add(() => gate.future);
      final second = q.add(() async => ran = true)..cancel();
      gate.complete();
      await first.future;
      await expectLater(second.future, throwsA(isA<RequestCancelled>()));
      expect(ran, isFalse);
    });

    test('background requests wait for every foreground one; a promoted one '
        'runs with them', () async {
      final q = RequestQueue(concurrency: 1);
      final gate = Completer<void>();
      final order = <String>[];
      Future<void> task(String name) async => order.add(name);
      final first = q.add(() => gate.future);
      q.add(() => task('sharper A'), background: true);
      final b = q.add(() => task('sharper B'), background: true);
      q
        ..add(() => task('thumb 1'))
        ..add(() => task('thumb 2'));
      b.promote();
      gate.complete();
      await first.future;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(order, ['sharper B', 'thumb 2', 'thumb 1', 'sharper A']);
    });
  });

  group('SharedRequests', () {
    test('callers share one run; it leaves the queue when all cancel before '
        'it starts', () async {
      final q = RequestQueue(concurrency: 1);
      final shared = SharedRequests<int>(q);
      final gate = Completer<void>();
      final blocker = q.add(() => gate.future);
      var runs = 0;
      Future<int> task(RequestSignal _) async => ++runs;
      const timeout = Duration(seconds: 5);
      final owner = Object();
      final a = shared.join('k', owner, task, timeout: timeout);
      final b = shared.join('k', owner, task, timeout: timeout);
      a.cancel();
      b.cancel();
      expect(q.pending, 0);
      final c = shared.join('k', owner, task, timeout: timeout);
      final d = shared.join('k', owner, task, timeout: timeout);
      gate.complete();
      await blocker.future;
      expect(await c.future, 1);
      expect(await d.future, 1);
      expect(runs, 1);
      await expectLater(a.future, throwsA(isA<RequestCancelled>()));
    });

    test('a request made on an earlier connection is not joined', () async {
      final shared = SharedRequests<int>(RequestQueue());
      final stuck = Completer<int>();
      const timeout = Duration(seconds: 5);
      final old = shared.join(
        'k',
        Object(),
        (_) => stuck.future,
        timeout: timeout,
      );
      final fresh = shared.join(
        'k',
        Object(),
        (_) async => 2,
        timeout: timeout,
      );
      expect(await fresh.future, 2);
      stuck.complete(1);
      expect(await old.future, 1);
    });

    test('past its deadline a run fails its callers and is aborted, but '
        'keeps its queue slot until it has ended', () async {
      final q = RequestQueue(concurrency: 1);
      final shared = SharedRequests<int>(q);
      final ends = Completer<int>();
      late RequestSignal signal;
      final ticket = shared.join('k', Object(), (s) {
        signal = s;
        return ends.future;
      }, timeout: const Duration(milliseconds: 50));
      await expectLater(ticket.future, throwsA(isA<TimeoutException>()));
      expect(signal.abandoned, isTrue);
      expect(await signal.aborted, isA<TimeoutException>());

      final next = q.add(() async => 'next');
      expect(q.running, 1, reason: 'the aborted run has not ended yet');
      expect(next.started, isFalse);
      ends.complete(1);
      expect(await next.future, 'next');
      expect(q.running, 0);
    });

    test('the last caller leaving aborts a run that asked for it', () async {
      final shared = SharedRequests<int>(RequestQueue());
      final ends = Completer<int>();
      late RequestSignal signal;
      shared
          .join(
            'k',
            Object(),
            (s) {
              signal = s;
              return ends.future;
            },
            timeout: const Duration(seconds: 5),
            abortWhenUnwanted: true,
          )
          .cancel();
      expect(await signal.aborted, isA<RequestCancelled>());
      ends.complete(1);
    });
  });
}
