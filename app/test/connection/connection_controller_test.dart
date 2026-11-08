import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';

import '../support/test_app.dart';

void main() {
  test('switching cameras while connected starts a new attempt', () async {
    final app = await createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      sessionOptions: const GrSessionOptions(
        scanTimeout: Duration(milliseconds: 600),
      ),
    );
    addTearDown(app.dispose);
    final connection = app.models.connection;

    await connection.connect();
    expect(connection.status, ConnectionStatus.connected);

    // RootScreen connects in the same tick in which the camera store
    // switches cameras; the controller disconnects from the old one.
    const other = GrPairedCamera(
      deviceId: 'AA:BB:CC:DD:EE:FF',
      serialNumber: '1111111',
      modelName: 'RICOH GR IIIx',
    );
    final added = app.models.cameras.add(
      SavedCamera(paired: other, name: 'GR IIIx', pairedAt: DateTime(2026)),
    );
    final attempt = connection.connect();
    expect(connection.status, ConnectionStatus.connecting);

    await added;
    await attempt;
    // The other camera is not around, so the new attempt fails; it must
    // not be overwritten by the old camera's disconnect.
    expect(connection.status, ConnectionStatus.failed);
    expect(connection.failure?.kind, ConnectFailureKind.unreachable);
  });
}
