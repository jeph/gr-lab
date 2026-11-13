import 'dart:convert';

import 'package:gr_protocol/src/http/http.dart';
import 'package:test/test.dart';

Map<String, Object?> obj(String text) => decodeCameraJson(text).object!;

void main() {
  group('decodeCameraJson', () {
    test('rewrites 4294967295 to -2147483648 like Image Sync', () {
      final json = decodeCameraJson('{"errCode":200,"remain":4294967295}');
      expect(json.object!['remain'], -2147483648);
      expect(json.text, '{"errCode":200,"remain":-2147483648}');
    });

    test('leaves longer numbers containing the digits alone', () {
      expect(
        applyUint32Quirk('[14294967295,42949672950,4294967295.5,4294967295]'),
        '[14294967295,42949672950,4294967295.5,-2147483648]',
      );
    });

    test('reports empty and malformed bodies without throwing', () {
      expect(decodeCameraJson('').issue, 'empty body');
      expect(decodeCameraJson('404 Not Found').issue, startsWith('not JSON'));
      expect(decodeCameraJson('404 Not Found').value, isNull);
      expect(decodeCameraJson('[1]').object, isNull);
      expect(decodeCameraJsonBytes(utf8.encode('{"a":"é"}')).object, {
        'a': 'é',
      });
      expect(decodeCameraJsonBytes([0x7B, 0xFF, 0x7D]).issue, isNotNull);
    });
  });

  group('GrEnvelope', () {
    test('reads errCode, errMsg and detail.reason', () {
      final e = GrEnvelope(
        obj(
          '{"errCode":400,"errMsg":"Bad Request", '
          '"detail":{"reason":"err_fw_same"}}',
        ),
      );
      expect(
        (e.errCode, e.errMsg, e.reason, e.ok),
        (400, 'Bad Request', 'err_fw_same', false),
      );
    });

    test('tolerates numeric strings, doubles and missing fields', () {
      expect(GrEnvelope({'errCode': '200'}).ok, isTrue);
      expect(GrEnvelope({'errCode': 200.0}).errCode, 200);
      expect(GrEnvelope({'errCode': 200.5}).errCode, isNull);
      expect(GrEnvelope({'errCode': true}).errCode, isNull);
      expect(GrEnvelope({}).reason, isNull);
      expect(GrEnvelope({'detail': 'x'}).reason, isNull);
    });
  });

  group('GrProps', () {
    final props = GrProps(
      obj('''
{
        "errCode":200,"model":"RICOH GR IV HDF","serialNo":"12345678",
        "firmwareVersion":"1.10","macAddress":"00:00:5E:00:53:55",
        "bdName":"GR_123456","ssid":"GR_123456","key":"secret",
        "battery":87,
        "storages":[{"name":"in","equipped":true,"writable":true,"remain":"120"},
                    {"name":"sd1","equipped":true,"writable":false,"remain":4294967295,"format":"rawdng"}],
        "av":"2.8","avList":["2.8","4.0","5.6"],
        "tv":"1.250","tvList":["1.250","1.500"],
        "xv":"+0.3","xvList":["-0.3","0.0","+0.3"],
        "WBMode":"auto","WBModeList":["auto","daylight"],
        "focusMode":"af",
        "shootMode":"single",
        "newKey":"v","newKeyList":["v","w"],
        "focusEffectiveArea":[78,75],
        "stateMovie":"idle",
        "vendorBlob":{"nested":[1,2]}
      }'''),
    );

    test('identity and status', () {
      expect(props.model, 'RICOH GR IV HDF');
      expect(
        props.identity,
        const GrCameraIdentity(
          model: 'RICOH GR IV HDF',
          serialNo: '12345678',
          bdName: 'GR_123456',
        ),
      );
      expect(props.wifiKey, 'secret');
      expect(props.battery, 87);
      expect(props.focusEffectiveArea, [78, 75]);
      expect(props.stateMovie, 'idle');
    });

    test('storages accept remain as string or number', () {
      final s = props.storages;
      expect(s.map((e) => e.name), ['in', 'sd1']);
      expect(s[0].remain, 120);
      expect(s[1].remain, -2147483648);
      expect(s[1].writable, isFalse);
      expect(s[1].format, 'rawdng');
    });

    test('settings pair values with <key>List, including unknown keys', () {
      final settings = props.settings;
      expect(
        settings.keys,
        containsAll(['av', 'tv', 'xv', 'WBMode', 'newKey', 'focusMode']),
      );
      expect(settings['tv']!.current, '1.250');
      expect(settings['focusMode']!.options, isNull);
      expect(settings.containsKey('sv'), isFalse);
      expect(props.setting('newKey')!.options, ['v', 'w']);
    });

    test('a value is only offered when listed', () {
      expect(props.offers('av', '4.0'), isTrue);
      expect(props.offers('av', '4'), isFalse);
      expect(props.offers('xv', '+0.3'), isTrue);
      expect(props.offers('focusMode', 'af'), isFalse, reason: 'no list');
      expect(props.offers('sv', '100'), isFalse, reason: 'absent');
    });

    test('unknown keys stay in raw', () {
      expect(props.raw['vendorBlob'], {
        'nested': [1, 2],
      });
    });

    test('numbers in setting lists are coerced to text', () {
      final p = GrProps({
        'sv': 100,
        'svList': [100, 'auto', null, 200],
      });
      expect(p.setting('sv')!.current, '100');
      expect(p.setting('sv')!.options, ['100', 'auto', '200']);
    });
  });

  group('photo models', () {
    test('photo list paths and after-cursor', () {
      final list = GrPhotoList(
        obj(
          '{"errCode":200,"dirs":['
          '{"name":"100RICOH","files":["R0000001.JPG","R0000002.DNG"]},'
          '{"name":"101RICOH","files":["R0000003.MOV"]},'
          '{"name":"102RICOH","files":[]}]}',
        ),
      );
      expect(list.fileCount, 3);
      expect(list.paths.map((p) => '$p'), [
        '100RICOH/R0000001.JPG',
        '100RICOH/R0000002.DNG',
        '101RICOH/R0000003.MOV',
      ]);
      expect(list.last, GrPhotoPath('101RICOH', 'R0000003.MOV'));
      expect(GrPhotoList({'errCode': 200}).last, isNull);
      expect(GrPhotoList({'dirs': 'bad'}).dirs, isEmpty);
    });

    test("photo info: gpsInfo's latitude and longitude, and no location "
        'for an empty, short or impossible one', () {
      GrPhotoLocation? location(Object? gpsInfo) =>
          GrPhotoInfo({'errCode': 200, 'gpsInfo': ?gpsInfo}).location;
      expect(
        location('35.681236,139.767125,40.0,2026-11-05T01:04:11,WGS84'),
        const GrPhotoLocation(35.681236, 139.767125),
      );
      expect(
        location('-33.856800,-70.650000,0.0,2026-11-05T01:04:11,WGS84'),
        const GrPhotoLocation(-33.8568, -70.65),
      );
      // The photo has no location.
      expect(location(''), isNull);
      expect(location(null), isNull);
      // Not the camera's form.
      expect(location('35.681236'), isNull);
      expect(location('north,east,0.0'), isNull);
      expect(location(',,0.0,2026-11-05T01:04:11,WGS84'), isNull);
      expect(location('NaN,139.767125,0.0'), isNull);
      // Not on Earth.
      expect(location('90.000001,0.000000,0.0'), isNull);
      expect(location('0.000000,-180.000001,0.0'), isNull);
      expect(location('90.000000,180.000000,0.0'), isNotNull);
    });

    test('transfer item download size follows GR WORLD', () {
      GrTransferItem item(String path, String? size) =>
          GrTransferItem({'index': 3, 'filepath': path, 'size': ?size});
      expect(
        item('100RICOH/R0000001.JPG?xs', null).downloadSize,
        GrImageSize.xs,
      );
      expect(item('100RICOH/R0000001.JPG', 'xs').downloadSize, GrImageSize.xs);
      expect(
        item('100RICOH/R0000002.DNG', 'xs').downloadSize,
        GrImageSize.full,
      );
      expect(
        item('100RICOH/R0000001.JPG', 'full').downloadSize,
        GrImageSize.full,
      );
      expect(
        item('100RICOH/R0000001.JPG?xs', null).path,
        GrPhotoPath('100RICOH', 'R0000001.JPG'),
      );
      expect(item('garbage', null).path, isNull);
      expect(item('a/b', null).index, 3);
    });

    test('focus result centers and area', () {
      final f = GrFocusResult(
        obj(
          '{"errCode":200,"captureId":12,"focused":true,"focusRunning":false,'
          '"focusCenters":[[50,50],[10,"x",20]],"focusEffectiveArea":[78,75]}',
        ),
      );
      expect(f.captureId, '12');
      expect(f.focusCenters, [
        [50, 50],
        [10, 20],
      ]);
      expect(f.focusEffectiveArea, [78, 75]);
    });
  });

  group('firmware rejection', () {
    test('maps errCode and reason like GR WORLD', () {
      expect(classifyFirmwareRejection(200, null), GrFirmwareRejection.none);
      expect(
        classifyFirmwareRejection(400, 'err_fw_same'),
        GrFirmwareRejection.sameVersion,
      );
      expect(
        classifyFirmwareRejection(400, 'err_fw_old'),
        GrFirmwareRejection.olderVersion,
      );
      expect(
        classifyFirmwareRejection(400, null),
        GrFirmwareRejection.badRequest,
      );
      expect(
        classifyFirmwareRejection(412, 'battery_too_low'),
        GrFirmwareRejection.batteryTooLow,
      );
      expect(
        classifyFirmwareRejection(412, 'other'),
        GrFirmwareRejection.preconditionFailed,
      );
      expect(
        classifyFirmwareRejection(503, null),
        GrFirmwareRejection.unexpected,
      );
    });
  });
}
