import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/looks/looks_store.dart';
import 'package:grlab/src/shoot/camera_error_code.dart';

/// Where reading the camera's Custom slots stands.
enum SlotsState {
  /// Waiting for the Bluetooth link, or for the Looks tab to show.
  idle,

  /// Turning the camera on and reading C1–C3.
  reading,

  /// [LooksModel.slots] holds what the camera reported.
  ready,

  /// Turning the camera on or reading the slots failed.
  failed,

  /// The camera's model has no Custom slots GR Lab can reach
  /// ([CameraFeature.lookSlots]).
  unsupported,
}

/// A look the camera did not take, for a snack bar.
final class LoadRefusal {
  const new(this.slot, this.code);

  /// The slot (1–3) the look was meant for.
  final int slot;

  /// The error's technical code ([cameraErrorCode]); null when it has none.
  final String? code;
}

/// The Looks tab's state: the camera's Custom slots C1–C3 for this visit,
/// matched against the user's saved looks ([LooksStore]).
///
/// Showing the tab turns the camera on, as GR WORLD's Remote does for
/// shooting, because a camera that is off does not serve its slots
/// \[inferred\]; then C1–C3 are read, once per visit.
final class LooksModel extends ChangeNotifier {
  new({required this.connection, required this.store}) {
    connection.addListener(_sync);
    store.addListener(_onChange);
    _sync();
  }

  final ConnectionController connection;
  final LooksStore store;

  final _refusals = StreamController<LoadRefusal>.broadcast();

  CameraSession? _session;
  CameraLooks? _looks;
  bool _visible = false;
  bool _disposed = false;
  int _run = 0;
  SlotsState _state = SlotsState.idle;
  String? _failureCode;
  int? _loading;

  /// A load the camera refused, for a snack bar.
  Stream<LoadRefusal> get refusals => _refusals.stream;

  SlotsState get state =>
      model.supports(CameraFeature.lookSlots) ? _state : SlotsState.unsupported;

  /// The technical code of the last failure to read the slots.
  String? get failureCode => _failureCode;

  /// What C1–C3 hold; null until read on this connection.
  List<LookSlot>? get slots => _looks?.slots;

  /// The slot (1–3) a load is being written to.
  int? get loading => _loading;

  /// The paired camera's model, for the slots and base images it offers.
  GrModel? get model => connection.camera?.model;

  /// A look the camera produced, whose header a new look copies
  /// (`Look.onBase`): a slot's look, else a saved look's; null when there
  /// is neither.
  Look? get template {
    for (final s in slots ?? const <LookSlot>[]) {
      if (s.look case final look?) return look;
    }
    for (final saved in store.looks) {
      if (saved.look case final look?) return look;
    }
    return null;
  }

  /// Whether the Looks tab is showing. Showing it turns the camera on and
  /// reads C1–C3 (once per visit).
  bool get visible => _visible;
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    if (value) _state = SlotsState.idle;
    _sync();
  }

  /// Reads the slots again after a failure.
  void retry() {
    if (_state != SlotsState.failed) return;
    _state = SlotsState.idle;
    _sync();
  }

  /// The saved look [slot] holds: one with the same base image and
  /// parameters, the one under the slot's name first.
  SavedLook? savedLookIn(LookSlot slot) {
    final inSlot = slot.look;
    if (inSlot == null) return null;
    SavedLook? same;
    for (final saved in store.looks) {
      final look = saved.look;
      if (look == null || !look.sameAs(inSlot)) continue;
      if (saved.name == slot.name) return saved;
      same ??= saved;
    }
    return same;
  }

  /// The slots (1–3) holding [look].
  List<int> slotsHolding(SavedLook look) => [
    for (final s in slots ?? const <LookSlot>[])
      if (savedLookIn(s)?.id == look.id) s.number,
  ];

  /// Loads [look] into slot [number] under [name]. A refusal goes to
  /// [refusals]; returns whether the camera took it.
  Future<bool> load(
    int number, {
    required String name,
    required Look look,
  }) async {
    final looks = _looks;
    if (looks == null || _loading != null) return false;
    _loading = number;
    notifyListeners();
    try {
      await looks.load(number, name: name, look: look);
      return true;
    } on Object catch (e) {
      if (!_disposed) _refusals.add(LoadRefusal(number, cameraErrorCode(e)));
      return false;
    } finally {
      _loading = null;
      _onChange();
    }
  }

  void _sync() {
    if (_disposed) return;
    final session = connection.cameraSession;
    if (!identical(session, _session)) _attach(session);
    final looks = _looks;
    final linked = looks != null && connection.bleLinked;
    if (_visible && linked && state == SlotsState.idle) {
      unawaited(_read(looks));
    }
    notifyListeners();
  }

  /// A new session (or none): the slots read on the last one are gone.
  void _attach(CameraSession? session) {
    _session = session;
    _run++;
    _looks?.removeListener(_onChange);
    _looks = session?.looks;
    _looks?.addListener(_onChange);
    _state = SlotsState.idle;
    _failureCode = null;
  }

  Future<void> _read(CameraLooks looks) async {
    final run = ++_run;
    _state = SlotsState.reading;
    _failureCode = null;
    notifyListeners();
    try {
      await looks.wake();
      await looks.readSlots();
    } on Object catch (e) {
      if (_disposed || run != _run) return;
      _state = SlotsState.failed;
      _failureCode = cameraErrorCode(e);
      notifyListeners();
      return;
    }
    if (_disposed || run != _run) return;
    _state = SlotsState.ready;
    notifyListeners();
  }

  void _onChange() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_sync);
    store.removeListener(_onChange);
    _looks?.removeListener(_onChange);
    unawaited(_refusals.close());
    super.dispose();
  }
}
