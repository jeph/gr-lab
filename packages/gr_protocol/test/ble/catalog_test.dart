import 'package:gr_protocol/src/ble/ble.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:test/test.dart';

void main() {
  test('UUIDs are canonical and unique; keys unique', () {
    final uuids = <String>{};
    final keys = <String>{};
    for (final c in GrBleCatalog.all) {
      expect(canonicalUuid(c.uuid), c.uuid, reason: c.key);
      expect(uuids.add(c.uuid), isTrue, reason: 'duplicate ${c.uuid}');
      expect(keys.add(c.key), isTrue, reason: 'duplicate ${c.key}');
      expect(canonicalUuid(c.service.uuid), c.service.uuid);
    }
  });

  test('lookup by key, any UUID form, or 16-bit DIS UUID', () {
    expect(
      GrBleCatalog.lookup('shutter-speed'),
      same(GrBleCatalog.shutterSpeed),
    );
    expect(
      GrBleCatalog.lookup('d3ce2aed-10fa-4648-833d-cd74c6f35905'),
      same(GrBleCatalog.shutterSpeed),
    );
    expect(GrBleCatalog.lookup('2A24'), same(GrBleCatalog.disModelNumber));
    expect(GrBleCatalog.lookup('nope'), isNull);
  });

  test('guarded characteristics are exactly the dangerous writes', () {
    final guarded = {
      for (final c in GrBleCatalog.all)
        if (c.guarded) c.key,
    };
    expect(guarded, {
      GrBleCatalog.cameraPower.key,
      GrBleCatalog.ssid.key,
      GrBleCatalog.passphrase.key,
      GrBleCatalog.wlanChannel.key,
      GrBleCatalog.wlanFrequency.key,
      GrBleCatalog.wlanSecurity.key,
      GrBleCatalog.bleEnableCondition.key,
      GrBleCatalog.pairedDeviceName.key,
      GrBleCatalog.firmwareUpdateAvailable.key,
      GrBleCatalog.firmwareUpdateStart.key,
      GrBleCatalog.firmwareUpdateResult.key,
    });
  });

  test('firmware presence per ble-imagesync.md §1', () {
    expect(GrBleCatalog.wlanChannel.onGr3, isTrue);
    expect(GrBleCatalog.wlanChannel.onGr4, isFalse);
    expect(GrBleCatalog.gradNd.onGr3, isFalse);
    expect(GrBleCatalog.gradNd.onGr4, isFalse);
    for (final c in GrBleCatalog.all) {
      if (c.service != GrBleServices.deviceInformation &&
          c.apps.length == 1 &&
          c.apps.single == GrBleApp.grWorld) {
        expect(c.onGr4, isTrue, reason: c.key);
      }
    }
  });

  test('discovery report diff against the catalog', () {
    final info = GrBleServices.cameraInformation.uuid;
    final report = GrBleDiscoveryReport.compare([
      BleServiceInfo(
        uuid: info.toLowerCase(),
        characteristics: [
          BleCharacteristicInfo(
            uuid: GrBleCatalog.modelName.uuid.toLowerCase(),
            properties: const {BleCharacteristicProperty.read},
          ),
          // Known characteristic under the wrong service counts as extra.
          BleCharacteristicInfo(
            uuid: GrBleCatalog.shutterSpeed.uuid,
            properties: const {BleCharacteristicProperty.read},
          ),
        ],
      ),
      const BleServiceInfo(
        uuid: '12345678-1234-1234-1234-123456789ABC',
        characteristics: [],
      ),
    ]);
    expect(report.present, [GrBleCatalog.modelName]);
    expect(report.isPresent(GrBleCatalog.modelName), isTrue);
    expect(report.missing, hasLength(GrBleCatalog.all.length - 1));
    expect(report.extraServices, ['12345678-1234-1234-1234-123456789ABC']);
    expect(
      report.extraCharacteristics.single.uuid,
      GrBleCatalog.shutterSpeed.uuid,
    );
    expect(report.extraCharacteristics.single.service, info);
  });

  test('identity covers the six Camera Information characteristics', () {
    expect(GrBleCatalog.identity, hasLength(6));
    for (final c in GrBleCatalog.identity) {
      expect(c.service, same(GrBleServices.cameraInformation));
      expect(c.readable, isTrue);
    }
  });
}
