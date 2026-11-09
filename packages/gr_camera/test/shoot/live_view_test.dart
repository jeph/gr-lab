import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'rig.dart';

void main() {
  late ShootRig rig;

  tearDown(() => rig.close());

  test('runs between start and stop: settings, frames, then nothing', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    expect(live.props, isNull);
    await rig.startLiveView();
    expect(live.props!.setting('av')!.current, '2.8');
    expect(live.frame.value, isNotNull);
    expect(live.canChangeSettings, isTrue);
    expect(rig.events('shoot.liveview.start'), hasLength(1));

    live.stop();
    expect(live.streaming, isFalse);
    expect(live.frame.value, isNull);
    expect(live.props, isNull, reason: 'read again on the next start');
    expect(live.canChangeSettings, isFalse);
    await live.focusAt(const Offset(.5, .5));
    expect(rig.camera.focusPoints, isEmpty);
  });

  test('quick taps run one focus at a time: the first, then the newest tap '
      'once it ends', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    await rig.startLiveView();
    for (final x in [.2, .4, .6, .8]) {
      live.focusAt(Offset(x, .5)).ignore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(live.focus!.state, FocusState.focusing);
    expect(live.focus!.at.dx, .8, reason: 'the mark moves to the newest tap');
    await until(
      () => rig.camera.focusPoints.length == 2,
      reason: 'the newest tap sent',
    );
    await until(
      () => live.focus?.state == FocusState.focused,
      reason: 'second focus ended',
    );
    expect(rig.camera.focusPoints.map((p) => p.$1), [20, 80]);
    expect(live.focus!.at.dx, .8);
    expect(rig.events('shoot.focus.queued'), hasLength(3));
  });

  test('a lens result that comes before the focus answer counts, and the '
      'next tap goes at once', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(bonded: true, lensBeforeFocusAnswer: true),
      wifi: true,
    );
    final live = rig.liveView;
    await rig.startLiveView();
    live.focusAt(const Offset(.2, .5)).ignore();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    live.focusAt(const Offset(.8, .5)).ignore();
    final watch = Stopwatch()..start();
    await until(
      () => rig.camera.focusPoints.length == 2,
      reason: 'the second tap sent',
    );
    // Without the early lens result the first focus would wait 3 s.
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(rig.events('shoot.focus.earlyLens'), isNotEmpty);
    await until(
      () => live.focus?.state == FocusState.focused,
      reason: 'second focus ended',
    );
  });

  test('a setting shows at once, and its answer keeps the lists the GR IV '
      'leaves out of it', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    await rig.startLiveView();
    final lists = live.props!.raw['effectList'];
    expect(lists, isNotNull);
    for (final effect in ['efc_monochrome', 'col_vivid']) {
      final change = live.setSetting('effect', effect);
      expect(live.props!.setting('effect')!.current, effect);
      await change;
      expect(live.props!.setting('effect')!.current, effect);
      expect(live.props!.raw['effectList'], lists);
    }
    expect(rig.events('shoot.setting'), hasLength(2));
  });

  test('a refused setting goes back and throws', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    await rig.startLiveView();
    await expectLater(live.setSetting('av', 'nonsense'), throwsA(anything));
    expect(live.props!.setting('av')!.current, '2.8');
    expect(rig.events('shoot.setting').single['error'], isNotNull);
  });

  test('the settings poll shows values the camera picks itself', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    await rig.startLiveView();
    // In Av the camera sets the shutter speed and announces nothing.
    rig.camera.cameraSets('tv', '1.1000');
    await until(
      () => live.props!.setting('tv')!.current == '1.1000',
      reason: 'poll',
    );
    expect(
      rig.events('shoot.props').where((e) => e['reason'] == 'poll'),
      isNotEmpty,
    );
  });

  test('turning the mode dial locks the mode settings until a read started '
      'after the move is in, without a Wi-Fi notice from the camera', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(
        bonded: true,
        announcesDialChanges: false,
        httpLatency: Duration(milliseconds: 300),
      ),
      wifi: true,
    );
    final remote = rig.remote;
    final live = rig.liveView;
    await remote.wake();
    remote.watching = true;
    await until(() => remote.exposure != null, reason: 'mode');
    await rig.startLiveView();
    expect(live.modeSettled, isTrue);
    expect(
      live.props!.setting('tv')!.options?.length ?? 0,
      lessThanOrEqualTo(1),
      reason: 'Av sets the shutter speed',
    );

    rig.camera.setExposureMode(BleExposureMode.m);
    await until(() => !live.modeSettled, reason: 'locked');
    expect(rig.events('shoot.modeDial'), hasLength(1));
    await until(() => live.modeSettled, reason: 'read for M');
    expect(live.props!.setting('tv')!.options!.length, greaterThan(1));
    expect(
      rig.events('shoot.props').where((e) => e['reason'] == 'modeDial'),
      isNotEmpty,
    );
  });

  test('a mode dial move while live view is stopped locks nothing; the next '
      'start reads the settings for the new mode', () async {
    rig = await ShootRig.start(wifi: true);
    final remote = rig.remote;
    final live = rig.liveView;
    remote.watching = true;
    await until(() => remote.exposure != null, reason: 'mode');
    await rig.startLiveView();
    live.stop();
    rig.camera.setExposureMode(BleExposureMode.m);
    await until(
      () => remote.exposure!.mode.known == BleExposureMode.m,
      reason: 'mode dial notification',
    );
    expect(rig.events('shoot.modeDial'), hasLength(1));
    expect(rig.events('shoot.modeDial.lock'), isEmpty);
    await rig.startLiveView();
    expect(live.modeSettled, isTrue);
    expect(live.props!.setting('tv')!.options!.length, greaterThan(1));
  });

  test('the orientation comes with the settings and follows the camera as '
      'it turns, without waiting for a poll', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    rig.camera.orientation = GrCameraOrientation.verticalLeft;
    await rig.startLiveView();
    expect(live.orientation, GrCameraOrientation.verticalLeft);

    rig.camera.orientation = GrCameraOrientation.positive;
    await until(
      () => live.orientation == GrCameraOrientation.positive,
      reason: 'turned level',
    );
    expect(rig.events('shoot.orientation').last, {
      'from': 'vertical_left',
      'to': 'positive',
      'reason': 'cameraDirect',
    });

    live.stop();
    expect(live.orientation, isNull, reason: 'read again on the next start');
  });

  test('a picture taken while live view runs becomes the last shot', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    await rig.remote.wake();
    await rig.startLiveView();
    expect(live.lastShot, isNull);
    await rig.remote.shutter();
    await until(() => live.lastShot != null, reason: 'thumbnail');
  });

  test('the last shot goes once the camera deletes its file', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    await rig.remote.wake();
    await rig.startLiveView();
    await rig.remote.shutter();
    await until(() => live.lastShot != null, reason: 'thumbnail');
    final shot = rig.camera.photos.last;

    var notified = 0;
    live.addListener(() => notified++);
    expect(rig.camera.removePhoto(shot.path, storage: shot.storage), isTrue);
    await until(() => live.lastShot == null, reason: 'last shot cleared');
    expect(notified, greaterThan(0));
    expect(rig.events('shoot.thumb.deleted'), [
      {
        'path': '${shot.path}',
        'storage': shot.storage,
        'shown': true,
        'loadsDropped': 0,
      },
    ]);
  });

  test('a thumbnail still loading when the camera deletes its file is not '
      'shown', () async {
    final asked = Completer<void>();
    final release = Completer<void>();
    final media = syntheticMedia();
    rig = await ShootRig.start(
      wifi: true,
      media: (photo, size) async {
        if (size == GrImageSize.thumb && !asked.isCompleted) {
          asked.complete();
          await release.future;
        }
        return await media(photo, size);
      },
    );
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final live = rig.liveView;
    await rig.remote.wake();
    await rig.startLiveView();
    await rig.remote.shutter();
    await asked.future;
    final shot = rig.camera.photos.last;

    rig.camera.removePhoto(shot.path, storage: shot.storage);
    await until(
      () => rig.events('shoot.thumb.deleted').isNotEmpty,
      reason: 'delete seen',
    );
    // The camera finishes the request it accepted before the delete.
    release.complete();
    await until(
      () => rig.events('shoot.thumb.dropped').isNotEmpty,
      reason: 'load ended',
    );
    expect(live.lastShot, isNull);
    expect(rig.events('shoot.thumb.deleted').single['loadsDropped'], 1);
  });

  test('closing the session stops live view', () async {
    rig = await ShootRig.start(wifi: true);
    final live = rig.liveView;
    await rig.startLiveView();
    await rig.session.close();
    expect(live.streaming, isFalse);
    expect(live.props, isNull);
    live.start();
    expect(live.started, isFalse);
  });
}
