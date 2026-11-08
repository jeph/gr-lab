import 'dart:async';

import '../trace.dart';
import 'client.dart';
import 'models.dart';

/// Image Sync's connection-loss rule (`ConnectionChecker.java:63-104`,
/// docs/protocol/connection-imagesync.md §2.2): the link is lost when
/// [failureThreshold] consecutive probes failed **and** at least [lossAfter]
/// passed since the last success. A probe that answers with a different
/// camera identity counts as a failure.
///
/// Image Sync compares `> 40000 ms`; this uses `>=` as the docs' summary
/// states "≥40 s" (§2.4). Time comes from the caller, so the rule is
/// deterministic.
final class LivenessTracker {
  LivenessTracker({
    required DateTime start,
    this.failureThreshold = 3,
    this.lossAfter = const Duration(seconds: 40),
  }) : _lastSuccess = start {
    if (failureThreshold < 1) {
      throw ArgumentError.value(failureThreshold, 'failureThreshold', '≥ 1');
    }
  }

  final int failureThreshold;
  final Duration lossAfter;
  DateTime _lastSuccess;
  int _failures = 0;
  bool _lost = false;

  int get consecutiveFailures => _failures;
  DateTime get lastSuccess => _lastSuccess;
  bool get lost => _lost;

  void recordSuccess(DateTime at) {
    if (_lost) return;
    _failures = 0;
    _lastSuccess = at;
  }

  /// Returns `true` when this failure declares the loss.
  bool recordFailure(DateTime at) {
    if (_lost) return false;
    _failures++;
    if (_failures >= failureThreshold &&
        at.difference(_lastSuccess) >= lossAfter) {
      _lost = true;
      return true;
    }
    return false;
  }
}

/// Result of one liveness probe.
final class LivenessPoll {
  const LivenessPoll({
    required this.at,
    required this.ok,
    required this.latency,
    required this.consecutiveFailures,
    required this.sinceLastSuccess,
    required this.lost,
    this.identity,
    this.identityMismatch = false,
    this.error,
  });

  final DateTime at;
  final bool ok;
  final Duration latency;

  /// Identity from this probe's `/v1/props`, when it answered.
  final GrCameraIdentity? identity;
  final bool identityMismatch;
  final Object? error;
  final int consecutiveFailures;
  final Duration sinceLastSuccess;

  /// This poll declared the connection lost.
  final bool lost;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'ok': ok,
    'latencyMs': latency.inMilliseconds,
    if (identity != null) 'identity': identity!.toJson(),
    if (identityMismatch) 'identityMismatch': true,
    if (error != null) 'error': '$error',
    'consecutiveFailures': consecutiveFailures,
    'sinceLastSuccessMs': sinceLastSuccess.inMilliseconds,
    'lost': lost,
  };
}

/// Polls `GET /v1/props` with a fixed delay between probes and applies the
/// [LivenessTracker] rule. Defaults follow Image Sync: 500 ms delay, 1 s
/// connect, 10 s read (connection-imagesync.md §2.2). This is a liveness
/// probe, not a proven keep-awake mechanism (connection-lifecycle.md §9).
final class LivenessMonitor {
  LivenessMonitor(
    GrHttpClient client, {
    Duration interval = const Duration(milliseconds: 500),
    Duration connectTimeout = const Duration(seconds: 1),
    Duration readTimeout = const Duration(seconds: 10),
    int failureThreshold = 3,
    Duration lossAfter = const Duration(seconds: 40),
    GrCameraIdentity? expectedIdentity,
    DateTime Function()? clock,
    TraceSink? trace,
  }) : this.withProbe(
         () =>
             client.props(connectTimeout: connectTimeout, timeout: readTimeout),
         interval: interval,
         failureThreshold: failureThreshold,
         lossAfter: lossAfter,
         expectedIdentity: expectedIdentity,
         clock: clock,
         trace: trace,
       );

  /// Uses [probe] instead of `/v1/props` (e.g. a network-bound client).
  LivenessMonitor.withProbe(
    this._probe, {
    this.interval = const Duration(milliseconds: 500),
    this.failureThreshold = 3,
    this.lossAfter = const Duration(seconds: 40),
    GrCameraIdentity? expectedIdentity,
    DateTime Function()? clock,
    this._trace,
  }) : _identity = expectedIdentity,
       _now = clock ?? DateTime.now;

  final Future<GrProps> Function() _probe;
  final Duration interval;
  final int failureThreshold;
  final Duration lossAfter;
  final DateTime Function() _now;
  final TraceSink? _trace;
  final StreamController<LivenessPoll> _polls = StreamController.broadcast();
  final Completer<LivenessPoll> _lost = Completer();
  GrCameraIdentity? _identity;
  LivenessTracker? _tracker;
  Timer? _timer;
  bool _running = false;

  /// Every probe result, in order.
  Stream<LivenessPoll> get polls => _polls.stream;

  /// Completes with the poll that declared the loss; polling stops then.
  Future<LivenessPoll> get lost => _lost.future;

  /// The camera identity being enforced: the expected one, or the first one
  /// seen.
  GrCameraIdentity? get identity => _identity;

  bool get running => _running;

  /// Starts polling; the first probe runs after [interval], like Image Sync's
  /// `scheduleWithFixedDelay(500, 500)`.
  void start() {
    if (_running || _lost.isCompleted) return;
    _running = true;
    _tracker ??= LivenessTracker(
      start: _now(),
      failureThreshold: failureThreshold,
      lossAfter: lossAfter,
    );
    _timer = Timer(interval, _tick);
  }

  Future<void> _tick() async {
    if (!_running) return;
    final poll = await pollOnce();
    if (poll.lost) {
      _running = false;
      return;
    }
    if (_running) _timer = Timer(interval, _tick);
  }

  /// Runs one probe now and applies the rule.
  Future<LivenessPoll> pollOnce() async {
    final tracker = _tracker ??= LivenessTracker(
      start: _now(),
      failureThreshold: failureThreshold,
      lossAfter: lossAfter,
    );
    final watch = Stopwatch()..start();
    GrCameraIdentity? seen;
    Object? error;
    var mismatch = false;
    try {
      final props = await _probe();
      seen = props.identity;
      final expected = _identity ??= seen;
      mismatch = expected != seen;
    } catch (e) {
      error = e;
    }
    watch.stop();
    final at = _now();
    final ok = error == null && !mismatch;
    var lost = false;
    if (ok) {
      tracker.recordSuccess(at);
    } else {
      lost = tracker.recordFailure(at);
    }
    final poll = LivenessPoll(
      at: at,
      ok: ok,
      latency: watch.elapsed,
      identity: seen,
      identityMismatch: mismatch,
      error: error,
      consecutiveFailures: tracker.consecutiveFailures,
      sinceLastSuccess: at.difference(tracker.lastSuccess),
      lost: lost,
    );
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.session,
        direction: TraceDirection.internal,
        kind: lost ? 'livenessLost' : 'livenessPoll',
        fields: poll.toJson(),
      ),
    );
    if (!_polls.isClosed) _polls.add(poll);
    if (lost && !_lost.isCompleted) _lost.complete(poll);
    return poll;
  }

  /// Stops polling and closes [polls].
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    await _polls.close();
  }
}
