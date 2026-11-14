/// Time the OS gives the app to finish work once it has left the screen
/// (iOS's background task), from `GrCameraEnvironment.backgroundTime`.
/// Hold it while leaving a camera: without it iOS suspends the app within
/// seconds, in the middle of the Bluetooth write and the network removal.
final class BackgroundTime {
  /// Time that ends with [end], which calls `end` once. [remaining] as the
  /// OS said when it was granted.
  new({this.remaining, this._end});

  /// Time that is not limited: the platform does not suspend an app that
  /// leaves the screen this way, or has nothing to give.
  new unlimited() : this();

  /// How long the OS said the app may still run when this was granted;
  /// null when it set no limit (the app was in front, or keeps running
  /// for another reason, such as live geotagging).
  final Duration? remaining;

  final Future<void> Function()? _end;
  bool _ended = false;

  /// Gives the time back. More than once is fine.
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    await _end?.call();
  }
}
