import 'package:gr_protocol/gr_protocol.dart';

/// The [PhoneLocation] of an environment built without one: the app may
/// never locate the phone, no position ever comes and no run can be held.
final class InertPhoneLocation implements PhoneLocation {
  /// A location service that never locates the phone.
  const new();

  @override
  Future<LocationAccess> access() async => LocationAccess.none;

  @override
  Stream<LocationAccess> get accessChanges => const Stream.empty();

  @override
  Future<LocationAccess> requestWhileInUse() async => LocationAccess.none;

  @override
  Future<LocationAccess> requestAlways() async => LocationAccess.none;

  @override
  Future<void> openSettings(LocationSettingsPage page) async {}

  @override
  Stream<LocationFix> get updates => const Stream.empty();

  @override
  Future<LocationFix?> current({required Duration timeout}) async => null;

  @override
  Future<void> holdRun(LocationRunNotice notice, {required bool awake}) async {
    throw const LocationRunException(LocationRunRefusal.unsupported);
  }

  @override
  Future<void> releaseRun() async {}

  @override
  Stream<void> get runStops => const Stream.empty();

  @override
  Future<void> setHistory({required bool enabled}) async {}

  @override
  Future<List<LocationFix>> takeHistory() async => const [];

  @override
  Stream<void> get historyPending => const Stream.empty();
}
