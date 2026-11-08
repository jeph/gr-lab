import 'dart:async';
import 'dart:collection';

/// Thrown into a request's future when it is cancelled before it started.
final class RequestCancelled implements Exception {
  const RequestCancelled();

  @override
  String toString() => 'RequestCancelled';
}

/// A queued camera request; [cancel] drops it if it has not started yet.
final class QueuedRequest<T> {
  QueuedRequest._(this._queue, this._task);

  final RequestQueue _queue;
  final Future<T> Function() _task;
  final Completer<T> _done = Completer<T>();
  bool _started = false;

  Future<T> get future => _done.future;

  void cancel() {
    if (_started || _done.isCompleted) return;
    _queue._pending.remove(this);
    _done.completeError(const RequestCancelled());
  }
}

/// Runs camera requests with at most [concurrency] in flight, so scrolling
/// the grid never floods the camera's small HTTP server. Newer requests run
/// first: they belong to the cells on screen now.
final class RequestQueue {
  RequestQueue({this.concurrency = 3});

  final int concurrency;
  final _pending = ListQueue<QueuedRequest<Object?>>();
  int _running = 0;

  int get running => _running;
  int get pending => _pending.length;

  QueuedRequest<T> add<T>(Future<T> Function() task) {
    final request = QueuedRequest<T>._(this, task);
    // Futures that are cancelled or fail without a listener must not
    // surface as unhandled errors.
    request.future.ignore();
    _pending.addFirst(request);
    _pump();
    return request;
  }

  /// Drops every request that has not started.
  void clear() {
    for (final r in _pending.toList()) {
      r.cancel();
    }
  }

  void _pump() {
    while (_running < concurrency && _pending.isNotEmpty) {
      final request = _pending.removeFirst();
      request._started = true;
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
