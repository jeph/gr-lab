import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/pairing/pairing_flow.dart';

import '../support/test_app.dart';

const _add = Key('pair-add-1234567');
const _find = Key('pairing-find');
const _instructions = Key('pairing-instructions');
const _progress = Key('pairing-progress');
const _failure = Key('pairing-failure');
const _done = Key('pairing-done');
const _close = Key('pairing-close');

/// The Material button inside the nearby row's Add button.
Finder get _addButton =>
    find.descendant(of: find.byKey(_add), matching: find.byType(FilledButton));

/// [finder] inside the pairing flow, not the Cameras screen under it.
Finder _inFlow(Finder finder) =>
    find.descendant(of: find.byType(PairingFlow), matching: finder);

Finder get _flowScrollable => _inFlow(find.byType(Scrollable)).first;

/// A phone-sized screen, so the pages lay out as on a device.
Future<TestApp> _create(
  WidgetTester tester, [
  FakeCameraConfig config = const FakeCameraConfig(),
  BleTransport Function(BleTransport camera)? transport,
]) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  return (await tester.runAsync(
    () => createTestApp(config: config, transport: transport),
  ))!;
}

/// Two cameras in range whose adverts carry the model but no serial (a
/// truncated Ricoh payload), so only the device id tells them apart.
final class _TwoCamerasWithoutSerials implements BleTransport {
  _TwoCamerasWithoutSerials(this._first, this._second, this._secondId);

  final BleTransport _first;
  final BleTransport _second;
  final String _secondId;

  static BleAdvertisement _withoutSerial(BleAdvertisement ad) {
    final ricoh = ad.manufacturerData[grRicohCompanyId]!;
    return BleAdvertisement(
      deviceId: ad.deviceId,
      rssi: ad.rssi,
      name: ad.name,
      // Marker and model tag only.
      manufacturerData: {grRicohCompanyId: Uint8List.sublistView(ricoh, 0, 3)},
      serviceUuids: ad.serviceUuids,
      connectable: ad.connectable,
    );
  }

  @override
  Future<BleAdapterState> adapterState() => _first.adapterState();

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    final subs = <StreamSubscription<BleAdvertisement>>[];
    late final StreamController<BleAdvertisement> out;
    out = StreamController<BleAdvertisement>(
      onListen: () {
        for (final t in [_first, _second]) {
          subs.add(
            t
                .scan(serviceUuids: serviceUuids)
                .map(_withoutSerial)
                .listen(out.add, onError: out.addError),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        await out.close();
      },
    );
    return out.stream;
  }

  @override
  Future<BleConnection> connect(String deviceId, {required Duration timeout}) =>
      (deviceId == _secondId ? _second : _first).connect(
        deviceId,
        timeout: timeout,
      );

  @override
  Future<void> close() async {
    await _first.close();
    await _second.close();
  }
}

/// The whole app with no camera paired yet, pairing opened from the
/// Cameras screen's Add a camera.
Future<TestApp> _start(
  WidgetTester tester, [
  FakeCameraConfig config = const FakeCameraConfig(),
]) async {
  final app = await _create(tester, config);
  await _open(tester, app);
  return app;
}

Future<void> _open(WidgetTester tester, TestApp app) async {
  await app.pumpApp(tester);
  await tapWhenReady(tester, find.byKey(const Key('cameras-add')));
  await pumpUntilFound(tester, find.byKey(_find));
}

/// From the find page to the running pairing attempt.
Future<void> _selectAndPair(WidgetTester tester, {Key add = _add}) async {
  await pumpUntilFound(tester, find.byKey(_find).hitTestable());
  // At large text the nearby list starts below the fold.
  await tester.drag(_flowScrollable, const Offset(0, -2000));
  await tester.pump();
  await tapWhenReady(tester, find.byKey(add));
  expect(find.byKey(_instructions), findsOneWidget);
  await tapWhenReady(tester, find.byKey(const Key('pair-start')));
}

/// Waits until the phone asks to check the code and the bond request has
/// reached [camera], so an OK pressed on it now is not lost: the screen
/// switches before the request arrives, and how long that takes depends on
/// the machine's load.
Future<void> _awaitCode(WidgetTester tester, FakeGrCamera camera) async {
  await pumpUntilFound(tester, find.text('Check the code'));
  await pumpUntil(
    tester,
    () => camera.pairingPending,
    reason: 'bond request on the camera',
  );
}

/// Pumps a screen with a button that pushes the flow, and opens it.
Future<void> _pushFlow(WidgetTester tester, TestApp app) async {
  await app.pumpWithin(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => PairingFlow.push(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    brightness: Brightness.dark,
  );
  await tapWhenReady(tester, find.text('open'));
  await pumpUntilFound(tester, find.byKey(_find));
}

void main() {
  testWidgets('pairs a nearby camera and hands over to the Cameras screen, '
      'linked over Bluetooth', (tester) async {
    final app = await _start(tester);

    expect(find.byKey(_find), findsOneWidget);
    expect(find.byKey(_close), findsOneWidget);
    await pumpUntilFound(tester, find.byKey(_add));
    expect(_inFlow(find.text('GR IV')), findsOneWidget);
    expect(find.textContaining('No. 1234567'), findsOneWidget);

    app.camera.openExecutePairing();
    await _selectAndPair(tester);
    expect(find.byKey(_progress), findsOneWidget);

    await _awaitCode(tester, app.camera);
    expect(app.models.cameras.current, isNull);
    app.camera.confirmPairing();

    await pumpUntilFound(tester, find.byKey(_done));
    final saved = app.models.cameras.current!;
    expect(saved.serial, '1234567');
    expect(saved.name, 'GR IV');
    expect(saved.paired.deviceId, const FakeCameraConfig().deviceId);
    expect(find.text('GR IV is paired'), findsOneWidget);
    expect(find.text('No. 1234567 · fw 1.20'), findsOneWidget);

    expect(app.models.settings.powerOnWhenConnecting, isTrue);
    await tapWhenReady(tester, find.byKey(const Key('pairing-done-power-on')));
    expect(app.models.settings.powerOnWhenConnecting, isFalse);

    // The pairing link was released, so the session links on its own,
    // over Bluetooth only.
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.bluetooth,
      reason: 'linked after pairing',
    );

    await tapWhenReady(tester, find.byKey(const Key('pairing-done-button')));
    await pumpUntil(tester, () => find.byKey(_done).evaluate().isEmpty);
    expect(find.byType(PairingFlow), findsNothing);
    expect(find.byKey(const Key('cameras')), findsOneWidget);
    expect(find.byType(LibraryScreen), findsNothing);
    expect(app.camera.wlanOn, isFalse);

    await tapWhenReady(tester, find.byKey(const Key('camera-card-library')));
    await pumpUntilFound(tester, find.byType(LibraryScreen));

    await app.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('a refused pairing shows the checklist and never retries '
        '(text ×$scale)', (tester) async {
      // Layout overflows at large text fail the test.
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await _start(
        tester,
        const FakeCameraConfig(executePairingOpen: true, refusePairing: true),
      );

      await _selectAndPair(tester);
      await pumpUntilFound(tester, find.byKey(_failure));
      expect(find.text("Pairing didn't finish"), findsOneWidget);
      // At large text the checklist runs below the fold.
      for (final text in [
        'Reopen Execute Pairing on the camera',
        'Paired this phone before?',
      ]) {
        await tester.scrollUntilVisible(
          find.text(text),
          200,
          scrollable: _flowScrollable,
        );
      }
      expect(app.ble.connects, 1);

      await tapWhenReady(tester, find.byKey(const Key('pair-again')));
      expect(find.byKey(_instructions), findsOneWidget);

      // Nothing starts another attempt until the user taps Pair.
      await pumpRounds(tester, 50);
      expect(find.byKey(_instructions), findsOneWidget);
      expect(app.ble.connects, 1);
      expect(app.models.cameras.current, isNull);

      await app.dispose();
    });
  }

  testWidgets('going back while confirming returns to the instructions', (
    tester,
  ) async {
    final app = await _start(
      tester,
      const FakeCameraConfig(executePairingOpen: true),
    );

    await _selectAndPair(tester);
    await _awaitCode(tester, app.camera);
    await tapWhenReady(tester, find.byKey(const Key('pairing-back')));
    expect(find.byKey(_instructions), findsOneWidget);

    // A late OK on the camera must not resurrect the stopped attempt.
    app.camera.confirmPairing();
    await pumpRounds(tester, 50);
    expect(find.byKey(_instructions), findsOneWidget);
    expect(find.byKey(_failure), findsNothing);
    expect(app.models.cameras.current, isNull);

    await app.dispose();
  });

  testWidgets('Bluetooth off is explained and Try again resumes scanning', (
    tester,
  ) async {
    final app = await _create(tester);
    app.camera.adapterState = BleAdapterState.poweredOff;
    await _open(tester, app);

    await pumpUntilFound(
      tester,
      find.byKey(const Key('pairing-bluetooth-off')),
    );
    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(app.ble.scans, 0);

    app.camera.adapterState = BleAdapterState.poweredOn;
    await tapWhenReady(tester, find.byKey(const Key('pairing-retry')));
    await pumpUntilFound(tester, find.byKey(_add));
    expect(app.ble.scans, 1);

    await app.dispose();
  });

  testWidgets('denied Bluetooth permission is explained', (tester) async {
    final app = await _create(tester);
    app.bluetoothPermission = false;
    await _open(tester, app);

    await pumpUntilFound(
      tester,
      find.byKey(const Key('pairing-bluetooth-denied')),
    );
    expect(app.ble.scans, 0);

    await app.dispose();
  });

  testWidgets('a camera that is off cannot be added until it turns on', (
    tester,
  ) async {
    final app = await _start(tester, const FakeCameraConfig(poweredOn: false));

    await pumpUntilFound(tester, _addButton);
    expect(find.text('Off · turn it on to pair'), findsOneWidget);
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);

    app.camera.poweredOn = true;
    await pumpUntil(
      tester,
      () => tester.widget<FilledButton>(_addButton).onPressed != null,
      reason: 'Add enabled',
    );
    expect(find.text('Off · turn it on to pair'), findsNothing);

    await app.dispose();
  });

  testWidgets('pushed as a route it shows a close button and pops', (
    tester,
  ) async {
    final app = await _create(tester);
    await _pushFlow(tester, app);

    await tapWhenReady(tester, find.byKey(_close));
    await pumpUntil(tester, () => find.byType(PairingFlow).evaluate().isEmpty);
    expect(find.text('open'), findsOneWidget);

    await app.dispose();
  });

  testWidgets('pushed as a route, cancelling while confirming pops it', (
    tester,
  ) async {
    final app = await _create(
      tester,
      const FakeCameraConfig(executePairingOpen: true),
    );
    await _pushFlow(tester, app);

    await _selectAndPair(tester);
    await _awaitCode(tester, app.camera);
    expect(find.byKey(_close), findsOneWidget);
    await tapWhenReady(tester, find.byKey(const Key('pairing-cancel')));
    await pumpUntil(tester, () => find.byType(PairingFlow).evaluate().isEmpty);
    expect(find.text('open'), findsOneWidget);

    // A late OK on the camera must not save anything.
    app.camera.confirmPairing();
    await pumpRounds(tester, 50);
    expect(app.models.cameras.current, isNull);
    expect(app.ble.connects, 1);

    await app.dispose();
  });

  testWidgets('closing while confirming stops pairing before a late OK', (
    tester,
  ) async {
    final app = await _create(
      tester,
      const FakeCameraConfig(executePairingOpen: true),
    );
    await _pushFlow(tester, app);

    await _selectAndPair(tester);
    await _awaitCode(tester, app.camera);
    await tapWhenReady(tester, find.byKey(_close));
    // OK pressed while the flow is still animating out.
    expect(find.byType(PairingFlow), findsOneWidget);
    app.camera.confirmPairing();

    await pumpUntil(tester, () => find.byType(PairingFlow).evaluate().isEmpty);
    await pumpRounds(tester, 50);
    expect(find.byKey(_done), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(app.models.cameras.current, isNull);

    await app.dispose();
  });

  testWidgets('a camera picked without a serial is the one that pairs', (
    tester,
  ) async {
    // The app's own camera (whose Wi-Fi and HTTP the session uses) is the
    // target; a decoy GR with Execute Pairing open advertises first.
    const targetId = '00:00:5E:00:53:B2';
    final decoyId = const FakeCameraConfig().deviceId;
    final decoy = FakeGrCamera(
      config: const FakeCameraConfig(executePairingOpen: true),
      media: syntheticMedia(),
    );
    final app = await _create(
      tester,
      const FakeCameraConfig(
        serial: '1234567',
        deviceId: targetId,
        bluetoothName: 'GR_TARGET',
        executePairingOpen: true,
      ),
      (camera) => _TwoCamerasWithoutSerials(decoy.transport, camera, targetId),
    );
    await _open(tester, app);

    // Rows are keyed by device id; a scan matching any GR would find the
    // decoy first.
    await pumpUntilFound(tester, find.byKey(Key('pair-add-$decoyId')));
    await _selectAndPair(tester, add: const Key('pair-add-$targetId'));
    await _awaitCode(tester, app.camera);
    app.camera.confirmPairing();

    await pumpUntilFound(tester, find.byKey(_done));
    // Pairing, then the session that starts once it is saved: never the
    // decoy.
    expect(app.ble.connected, isNotEmpty);
    expect(app.ble.connected, everyElement(targetId));
    expect(app.models.cameras.current?.serial, '1234567');
    expect(app.models.cameras.current?.paired.deviceId, targetId);

    await app.dispose();
    await tester.runAsync(decoy.close);
  });
}
