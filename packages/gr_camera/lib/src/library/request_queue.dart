import 'dart:async';
import 'dart:collection';

/// Thrown into a request's future when it is cancelled before it started,
/// or into a [RequestTicket] its holder cancelled.
final class RequestCancelled implements Exception {
  /// Carries no detail.
  const new();

  @override
  String toString() => 'RequestCancelled';
}

/// A queued camera request; [cancel] drops it if it has not started yet.
final class QueuedRequest<T> {
  new _(this._queue, this._task, this._background);

  final RequestQueue _queue;
  final Future<T> Function() _task;
  final Completer<T> _done = Completer<T>();
  bool _background;
  bool _started = false;

  /// The task's result or error, or [RequestCancelled] after [cancel].
  Future<T> get future => _done.future;

  /// The task has been handed to the camera; [cancel] no longer drops it.
  bool get started => _started;

  /// Drops the request if it has not started; [future] then fails with
  /// [RequestCancelled].
  void cancel() {
    if (_started || _done.isCompleted) return;
    _queue._pendingFor(_background).remove(this);
    _done.completeError(const RequestCancelled());
  }

  /// Moves a waiting background request ahead of every other background
  /// request and among the foreground ones, now that a screen waits on it.
  void promote() {
    if (!_background || _started || _done.isCompleted) return;
    _queue._background.remove(this);
    _background = false;
    _queue._foreground.addFirst(this);
  }
}

/// Runs camera requests with at most [concurrency] in flight, so scrolling
/// the grid never floods the camera's small HTTP server. Newer requests run
/// first: they belong to the cells on screen now. Background requests (a
/// sharper copy of an image already shown) run only when no foreground one
/// waits.
final class RequestQueue {
  /// A queue running at most [concurrency] requests at once.
  new({this.concurrency = 3});

  /// Requests in flight at most.
  final int concurrency;
  final _foreground = ListQueue<QueuedRequest<Object?>>();
  final _background = ListQueue<QueuedRequest<Object?>>();
  int _running = 0;

  /// Requests in flight now.
  int get running => _running;

  /// Requests waiting to start.
  int get pending => _foreground.length + _background.length;

  ListQueue<QueuedRequest<Object?>> _pendingFor(bool background) =>
      background ? _background : _foreground;

  /// Queues [task] ahead of the other waiting requests of its kind; a
  /// [background] one runs only when no foreground one waits.
  QueuedRequest<T> add<T>(
    Future<T> Function() task, {
    bool background = false,
  }) {
    final request = QueuedRequest<T>._(this, task, background);
    // Futures that are cancelled or fail without a listener must not
    // surface as unhandled errors.
    request.future.ignore();
    _pendingFor(background).addFirst(request);
    _pump();
    return request;
  }

  /// Drops every request that has not started.
  void clear() {
    for (final r in [..._foreground, ..._background]) {
      r.cancel();
    }
  }

  void _pump() {
    while (_running < concurrency && pending > 0) {
      final request =
          (_foreground.isNotEmpty
                ? _foreground.removeFirst()
                : _background.removeFirst())
            .._started = true;
      _running++;
      unawaited(_run(request));
    }
  }

  Future<void> _run<T>(QueuedRequest<T> request) async {
    try {
      request._done.complete(await request._task());
    } catch (e, st) {
      request._done.completeError(e, st);
    } finally {
      _running--;
      _pump();
    }
  }
}

/// Tells a started task that nobody waits for it any more (or that it ran
/// past its deadline), so it can close its camera request at once.
final class RequestSignal {
  final Completer<Object> _aborted = Completer<Object>();

  /// The task should stop: no caller waits for it, or its deadline passed.
  bool get abandoned => _aborted.isCompleted;

  /// Completes, with the error the task should end with, when the task is
  /// [abandoned]; pass it to the HTTP client as its `abort`.
  Future<Object> get aborted => _aborted.future;

  void _abandon(Object reason) {
    if (!_aborted.isCompleted) _aborted.complete(reason);
  }
}

/// One caller's wait on a [SharedRequests] request.
final class RequestTicket<T> {
  new _(this._leave) {
    _done.future.ignore();
  }

  /// A ticket already holding [value] (a cache hit).
  new done(T value) : _leave = null {
    _done.complete(value);
  }

  final void Function(RequestTicket<T>)? _leave;
  final Completer<T> _done = Completer<T>();

  /// The result, the request's error, or [RequestCancelled] once [cancel]
  /// was called.
  Future<T> get future => _done.future;

  /// Stops waiting; the shared request leaves the queue once no caller
  /// waits on it.
  void cancel() {
    if (_done.isCompleted) return;
    _done.completeError(const RequestCancelled());
    _leave?.call(this);
  }

  void _complete(T value) {
    if (!_done.isCompleted) _done.complete(value);
  }

  void _fail(Object error, StackTrace stack) {
    if (!_done.isCompleted) _done.completeError(error, stack);
  }
}

final class _Flight<T> {
  new(this.owner, {required this.abortWhenUnwanted});

  final Object owner;
  final bool abortWhenUnwanted;
  final RequestSignal signal = RequestSignal();
  final Set<RequestTicket<T>> waiters = {};
  late final QueuedRequest<T> request;
}

/// Queued requests that every caller asking for the same key shares. A
/// request leaves the queue once all its callers cancelled before it
/// started. Each run has a deadline: past it the callers get an error at
/// once and the run is aborted, but its queue slot stays taken until the
/// run has ended, so a camera that stops answering never has more requests
/// open than the queue allows.
final class SharedRequests<T> {
  /// Shared requests run on [queue].
  new(this.queue);

  /// Queue the shared requests run on.
  final RequestQueue queue;
  final _flights = <String, _Flight<T>>{};

  /// Waits on the request for [key], queueing [task] when there is none
  /// made through [owner] (the connection: a request on a link that has
  /// since gone is never joined). A run longer than [timeout] fails with
  /// [TimeoutException] and its signal is abandoned. With
  /// [abortWhenUnwanted], a started run is abandoned as soon as its last
  /// caller cancels; otherwise it finishes for whoever asks next.
  RequestTicket<T> join(
    String key,
    Object owner,
    Future<T> Function(RequestSignal signal) task, {
    required Duration timeout,
    bool background = false,
    bool abortWhenUnwanted = false,
  }) {
    var flight = _flights[key];
    if (flight == null || !identical(flight.owner, owner)) {
      final f = flight = _Flight<T>(
        owner,
        abortWhenUnwanted: abortWhenUnwanted,
      );
      f.request = queue.add(
        () => _run(key, f, task, timeout),
        background: background,
      );
      _flights[key] = f;
      unawaited(
        f.request.future.then(
          (value) => _settle(key, f, (w) => w._complete(value)),
          onError: (Object e, StackTrace st) =>
              _settle(key, f, (w) => w._fail(e, st)),
        ),
      );
    } else if (!background) {
      flight.request.promote();
    }
    final f = flight;
    final ticket = RequestTicket<T>._((t) => _leave(key, f, t));
    f.waiters.add(ticket);
    return ticket;
  }

  /// Runs [task] for [flight]. Past [timeout] its callers fail at once and
  /// its signal is abandoned, but the run holds its queue slot until
  /// [task] has ended (aborted, or by its own HTTP deadline).
  Future<T> _run(
    String key,
    _Flight<T> flight,
    Future<T> Function(RequestSignal signal) task,
    Duration timeout,
  ) async {
    final deadline = Timer(timeout, () {
      final error = TimeoutException('No answer within $timeout', timeout);
      flight.signal._abandon(error);
      _settle(key, flight, (w) => w._fail(error, StackTrace.current));
    });
    try {
      return await task(flight.signal);
    } finally {
      deadline.cancel();
    }
  }

  /// Ends [flight] for its callers; a caller arriving next starts afresh.
  void _settle(
    String key,
    _Flight<T> flight,
    void Function(RequestTicket<T> waiter) end,
  ) {
    _drop(key, flight);
    flight.waiters.forEach(end);
  }

  void _leave(String key, _Flight<T> flight, RequestTicket<T> ticket) {
    flight.waiters.remove(ticket);
    if (flight.waiters.isNotEmpty) return;
    if (!flight.request.started) {
      // Dropped at once, so a caller arriving next starts afresh instead of
      // joining a cancelled request.
      _drop(key, flight);
      flight.request.cancel();
    } else if (flight.abortWhenUnwanted) {
      _drop(key, flight);
      flight.signal._abandon(const RequestCancelled());
    }
  }

  void _drop(String key, _Flight<T> flight) {
    if (identical(_flights[key], flight)) _flights.remove(key);
  }
}
