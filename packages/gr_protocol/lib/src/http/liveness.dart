import 'dart:async';

import 'package:gr_protocol/src/http/client.dart';
import 'package:gr_protocol/src/trace.dart';

/// Image Sync's connection-loss rule (`ConnectionChecker.java:63-104`,
/// research/protocol/connection-imagesync.md §2.2): the link is lost when
/// [failureThreshold] consecutive probes failed **and** at least [lossAfter]
/// passed since the last success.
///
/// Image Sync compares `> 40000 ms`; this uses `>=` as the docs' summary
/// states "≥40 s" (§2.4). Time comes from the caller, so the rule is
/// deterministic.
final class LivenessTracker {
  /// Tracker whose loss clock starts at [start].
  new({
    required DateTime start,
    this.failureThreshold = 3,
    this.lossAfter = const Duration(seconds: 40),
  }) : _lastSuccess = start {
    if (failureThreshold < 1) {
      throw ArgumentError.value(failureThreshold, 'failureThreshold', '≥ 1');
    }
  }

  /// Consecutive failed probes needed before loss can be declared (≥ 1).
  final int failureThreshold;

  /// Minimum time since the last success before loss can be declared.
  final Duration lossAfter;
  DateTime _lastSuccess;
  int _failures = 0;
  bool _lost = false;

  /// Failed probes since the last success.
  int get consecutiveFailures => _failures;

  /// Time of the last successful probe, or the start time.
  DateTime get lastSuccess => _lastSuccess;

  /// Whether loss was declared; the tracker then ignores further probes.
  bool get lost => _lost;

  /// Records a successful probe at [at] and resets the failure count.
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
  /// Poll result with the tracker's state after it.
  const new({
    required this.at,
    required this.ok,
    required this.latency,
    required this.consecutiveFailures,
    required this.sinceLastSuccess,
    required this.lost,
    this.error,
  });

  /// When the probe finished.
  final DateTime at;

  /// Whether the camera answered the probe.
  final bool ok;

  /// Time the probe took.
  final Duration latency;

  /// Why the probe failed, if it did.
  final Object? error;

  /// Failed probes since the last success, this one included.
  final int consecutiveFailures;

  /// Time since the last successful probe.
  final Duration sinceLastSuccess;

  /// This poll declared the connection lost.
  final bool lost;

  /// Trace/log form.
  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'ok': ok,
    'latencyMs': latency.inMilliseconds,
    if (error != null) 'error': '$error',
    'consecutiveFailures': consecutiveFailures,
    'sinceLastSuccessMs': sinceLastSuccess.inMilliseconds,
    'lost': lost,
  };
}

/// Probes the camera with a fixed delay between probes and applies the
/// [LivenessTracker] rule. The rule and the timeouts (1 s connect, 10 s
/// read) are Image Sync's, which polls `GET /v1/props` every 500 ms
/// (connection-imagesync.md §2.2). Its poll also refreshes its settings;
/// this one only asks whether the camera still answers, so it probes
/// `GET /v1/ping` every 5 s \[design\]: GR III/IV firmware answers a ping
/// from the camera clock alone, where `/v1/props` gathers its status,
/// parameters, device, lens and supported-value lists
/// (firmware-protocol-inventory.md "Additional-route verification",
/// remote-shooting.md §4.2). A GR IV HDF (fw 1.20, 2026-11-11) answered
/// every ping within 75 ms (hardware-validation.md §4); no GR III has been
/// tried. This is a liveness probe, not a proven keep-awake mechanism
/// (connection-lifecycle.md §9).
///
/// With 5 s between probes the rule finds a loss 40 to 45 s after the
/// last answer (45 s when each probe runs into the read timeout), against
/// 40 to 42 s at 500 ms.
final class LivenessMonitor {
  /// Monitor probing [client]'s `/v1/ping` with [connectTimeout] and
  /// [readTimeout]. An answer that is an error, or is not a JSON object,
  /// fails the probe as no answer does.
  new(
    GrHttpClient client, {
    Duration interval = const Duration(seconds: 5),
    Duration connectTimeout = const Duration(seconds: 1),
    Duration readTimeout = const Duration(seconds: 10),
    int failureThreshold = 3,
    Duration lossAfter = const Duration(seconds: 40),
    DateTime Function()? clock,
    TraceSink? trace,
  }) : this.withProbe(
         () =>
             client.ping(connectTimeout: connectTimeout, timeout: readTimeout),
         interval: interval,
         failureThreshold: failureThreshold,
         lossAfter: lossAfter,
         clock: clock,
         trace: trace,
       );

  /// Uses `probe` instead (e.g. a network-bound client), which fails by
  /// throwing.
  new withProbe(
    this._probe, {
    this.interval = const Duration(seconds: 5),
    this.failureThreshold = 3,
    this.lossAfter = const Duration(seconds: 40),
    DateTime Function()? clock,
    this._trace,
  }) : _now = clock ?? DateTime.now;

  final Future<void> Function() _probe;

  /// Delay between the end of one probe and the start of the next.
  final Duration interval;

  /// Consecutive failures needed before loss (see [LivenessTracker]).
  final int failureThreshold;

  /// Time since the last success needed before loss.
  final Duration lossAfter;
  final DateTime Function() _now;
  final TraceSink? _trace;
  final StreamController<LivenessPoll> _polls = StreamController.broadcast();
  final Completer<LivenessPoll> _lost = Completer();
  LivenessTracker? _tracker;
  Timer? _timer;
  bool _running = false;

  /// Every probe result, in order.
  Stream<LivenessPoll> get polls => _polls.stream;

  /// Completes with the poll that declared the loss; polling stops then.
  Future<LivenessPoll> get lost => _lost.future;

  /// Whether polling is scheduled.
  bool get running => _running;

  /// Starts polling; the first probe runs after [interval], as Image Sync's
  /// `scheduleWithFixedDelay` does.
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
    Object? error;
    try {
      await _probe();
    } on Object catch (e) {
      error = e;
    }
    watch.stop();
    final at = _now();
    final ok = error == null;
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
