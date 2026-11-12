import 'dart:async';

import 'package:gr_protocol/gr_protocol.dart';

/// A simulated platform watch for cameras being switched on, scripted by a
/// test: it records which cameras it was told to watch and reports the
/// sightings the test makes.
final class FakePowerOnWatch implements PowerOnWatch {
  /// A watch the platform has when [supported]. With [needsAssociation]
  /// a camera has to be associated first, as on Android; without, every
  /// camera counts as associated, as on iOS.
  new({bool supported = true, this.needsAssociation = false})
    : isSupported = supported;

  /// What [supported] answers.
  bool isSupported;

  /// A camera is only [associated] once [associate] succeeded for it (or
  /// its id is in [associatedIds]); false counts every camera as
  /// associated.
  bool needsAssociation;

  /// Whether the user accepts the prompt [associate] shows.
  bool associateAnswer = true;

  /// Device ids of the cameras that have an association.
  final Set<String> associatedIds = {};

  /// Device ids of sightings that started the app; [takeLaunchSightings]
  /// hands them over and empties the list.
  final List<String> launchSightings = [];

  final _associateRequests = <WatchedCamera>[];
  final _watchCalls = <List<WatchedCamera>>[];
  final _sightings = StreamController<String>.broadcast();

  /// The watched cameras not yet reported since the last [watch].
  final _armed = <String>{};
  List<WatchedCamera> _watched = const [];

  /// Every camera [associate] was called for, in order.
  List<WatchedCamera> get associateRequests =>
      List.unmodifiable(_associateRequests);

  /// The cameras watched now.
  List<WatchedCamera> get watched => _watched;

  /// The cameras of every [watch] call, in order.
  List<List<WatchedCamera>> get watchCalls => List.unmodifiable(_watchCalls);

  /// The camera at [deviceId] advertises in its on state. [sightings]
  /// emits it only when the platform can watch, the camera is watched and
  /// it was not reported since the last [watch]: a watch reports a camera
  /// once and has to be started afresh to report it again.
  void sight(String deviceId) {
    if (!isSupported || !_armed.remove(deviceId)) return;
    _sightings.add(deviceId);
  }

  /// Ends [sightings].
  Future<void> close() => _sightings.close();

  @override
  Future<bool> supported() async => isSupported;

  @override
  Future<bool> associated(String deviceId) async =>
      !needsAssociation || associatedIds.contains(deviceId);

  @override
  Future<bool> associate(WatchedCamera camera) async {
    _associateRequests.add(camera);
    if (needsAssociation && associateAnswer) {
      associatedIds.add(camera.deviceId);
    }
    return await associated(camera.deviceId);
  }

  @override
  Future<void> watch(List<WatchedCamera> cameras) async {
    _watched = List.unmodifiable(cameras);
    _watchCalls.add(_watched);
    _armed
      ..clear()
      ..addAll([for (final camera in cameras) camera.deviceId]);
  }

  @override
  Stream<String> get sightings => _sightings.stream;

  @override
  Future<List<String>> takeLaunchSightings() async {
    final taken = List.of(launchSightings);
    launchSightings.clear();
    return taken;
  }
}
