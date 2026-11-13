import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/platform/window_pose.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowPose.fromChannel', () {
    test('reads the bar, the fold and the occlusions', () {
      final pose = WindowPose.fromChannel(const {
        'bar': 'right',
        'fold': [455.5, 0.0, 40.0, 669.0],
        'foldActive': true,
        'hinge': 'partiallyOpen',
        'occlusions': [
          [867.0, 0.0, 84.0, 124.0],
        ],
      });
      expect(pose.barSide, BarSide.right);
      expect(pose.fold, const Rect.fromLTRB(455.5, 0, 495.5, 669));
      expect(pose.halfOpen, isTrue);
      expect(pose.occlusions, const [Rect.fromLTRB(867, 0, 951, 124)]);
    });

    test('leaves out what is missing or malformed', () {
      expect(WindowPose.fromChannel(const {}), WindowPose.none);
      final pose = WindowPose.fromChannel(const {
        'bar': 'top',
        'fold': [1, 2, 3],
        'foldActive': 'yes',
        'occlusions': [
          'status',
          [0, 0, 10, 'ten'],
          [0, 0, 10, 10],
        ],
      });
      expect(pose.barSide, isNull);
      expect(pose.fold, isNull);
      expect(pose.halfOpen, isFalse);
      expect(pose.occlusions, const [Rect.fromLTRB(0, 0, 10, 10)]);
    });
  });

  group('PlatformWindowPose', () {
    const channel = MethodChannel('io.jeph.grphoto/window');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    /// Tells the Dart side of a change, as the iOS runner does.
    Future<void> changed(Map<String, Object?> pose) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('changed', pose)),
          (_) {},
        );

    test('reads the pose, then follows every change', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'get');
        return {'bar': 'right', 'occlusions': <Object?>[]};
      });
      final pose = PlatformWindowPose();
      addTearDown(pose.dispose);
      expect(pose.value, WindowPose.none);
      await pumpEventQueue();
      expect(pose.value.barSide, BarSide.right);

      var notified = 0;
      pose.addListener(() => notified++);
      await changed({
        'fold': [0.0, 455.5, 669.0, 40.0],
        'foldActive': true,
      });
      expect(pose.value.barSide, isNull);
      expect(pose.value.fold, const Rect.fromLTRB(0, 455.5, 669, 495.5));
      expect(pose.value.halfOpen, isTrue);
      expect(notified, 1);

      await changed({
        'fold': [0.0, 455.5, 669.0, 40.0],
        'foldActive': true,
        'hinge': 'partiallyOpen',
      });
      expect(notified, 1, reason: 'the same pose');
    });

    test('stays without a pose where the platform has none to give', () async {
      // Android: nothing answers the channel.
      final absent = PlatformWindowPose();
      addTearDown(absent.dispose);
      await pumpEventQueue();
      expect(absent.value, WindowPose.none);

      // An iOS before 27.1 answers with nothing in it.
      messenger.setMockMethodCallHandler(channel, (call) async => {});
      final old = PlatformWindowPose();
      await pumpEventQueue();
      expect(old.value, WindowPose.none);
      old.dispose();

      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'failed'),
      );
      final failing = PlatformWindowPose();
      addTearDown(failing.dispose);
      await pumpEventQueue();
      expect(failing.value, WindowPose.none);
    });
  });
}
