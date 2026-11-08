import 'package:gr_protocol/gr_protocol.dart';

/// What [SettingWrites] had when a settings read started.
typedef ReadMark = ({int epoch, int answered, int read});

/// The camera settings live view shows: the last ones the camera reported,
/// with the changes still waiting for its answer on top. The dial sends a
/// change without waiting for the one before, so answers and failures can
/// come back in any order; each change has a number to tell them apart.
final class SettingWrites {
  GrProps? _confirmed;
  GrProps? _shown;
  var _latest = 0;

  /// The newest change whose answer is in [_confirmed].
  var _answered = 0;

  /// Changes up to this number were made before the last [clear]; their
  /// results are dropped.
  var _cleared = 0;

  /// Counts [clear]s, so a read from before one is dropped.
  var _epoch = 0;

  /// Counts started reads.
  var _reads = 0;

  /// The newest started read whose result is in [_confirmed]: reads are
  /// not answered in the order they were sent, and an older one may have
  /// the settings of a mode the dial has left.
  var _readApplied = 0;

  /// Reads started before the mode dial last moved; their lists may
  /// belong to the old mode.
  var _readsBeforeMode = 0;

  /// Changes made before the mode dial last moved; their answers may
  /// carry the old mode's lists.
  var _changesBeforeMode = 0;

  /// Changes not answered yet, by key, oldest first: number and value.
  final _pending = <String, List<(int, String)>>{};

  /// What to show: [_confirmed] with the pending changes on top.
  GrProps? get props => _shown;

  /// Call when a settings read starts; pass the mark to [read] with its
  /// result.
  ReadMark startRead() => (epoch: _epoch, answered: _answered, read: ++_reads);

  /// Settings read from the camera by a read that started at [since]. A
  /// change answered since then may be missing from it (the camera may
  /// have read its settings before taking the change), so it is dropped,
  /// as is a read started before one already used.
  void read(GrProps next, {required ReadMark since}) {
    if (since.epoch != _epoch || _answered != since.answered) return;
    if (since.read < _readApplied) return;
    _readApplied = since.read;
    _confirmed = _merged(next);
    _show();
  }

  /// The mode dial moved: the settings it decides wait for a read
  /// started after this.
  void modeChanged() {
    _readsBeforeMode = _reads;
    _changesBeforeMode = _latest;
  }

  /// Whether the settings in use come from a read started after the mode
  /// dial last moved.
  bool get modeSettled => _readApplied > _readsBeforeMode;

  void clear() {
    _cleared = ++_latest;
    _epoch++;
    _confirmed = null;
    _shown = null;
    _pending.clear();
  }

  /// Shows [value] for [key] at once; returns the change's number.
  int begin(String key, String value) {
    final change = ++_latest;
    (_pending[key] ??= []).add((change, value));
    _show();
    return change;
  }

  /// The camera took [change] and answered with [answer]. An answer older
  /// than one already used is dropped: it may lack a newer change.
  void succeeded(int change, String key, GrProps answer) {
    if (change < _cleared) return;
    // Older changes of [key] were sent before this one, so the camera
    // has handled them too.
    _settle(key, (c) => c <= change);
    // Once a read for the current mode is in, an answer to a change made
    // before the dial moved is older than it: the camera may have
    // answered in the old mode.
    final fromOldMode = change <= _changesBeforeMode && modeSettled;
    if (change > _answered && !fromOldMode) {
      _answered = change;
      _confirmed = _merged(answer);
    }
    _show();
  }

  /// The camera refused [change] or did not answer: [key] shows what the
  /// camera last reported, or a newer change of it.
  void failed(int change, String key) {
    if (change < _cleared) return;
    _settle(key, (c) => c == change);
    _show();
  }

  void _settle(String key, bool Function(int change) done) {
    final changes = _pending[key];
    if (changes == null) return;
    changes.removeWhere((c) => done(c.$1));
    if (changes.isEmpty) _pending.remove(key);
  }

  void _show() {
    final confirmed = _confirmed;
    _shown = confirmed == null || _pending.isEmpty
        ? confirmed
        : GrProps({
            ...confirmed.raw,
            for (final MapEntry(:key, value: changes) in _pending.entries)
              key: changes.last.$2,
          });
  }

  /// [next] over the settings already read, keeping a `<key>List` that
  /// [next] leaves out: the GR IV's answer to a change has no
  /// `CameraConstants` lists (Image Control, metering, …;
  /// remote-shooting.md §4.2), which would leave nothing to pick from.
  GrProps _merged(GrProps next) {
    final before = _confirmed;
    if (before == null) return next;
    return GrProps({
      for (final e in before.raw.entries)
        if (e.key.endsWith('List') && !next.raw.containsKey(e.key))
          e.key: e.value,
      ...next.raw,
    });
  }
}
