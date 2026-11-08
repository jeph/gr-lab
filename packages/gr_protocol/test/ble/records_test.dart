import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:test/test.dart';

Uint8List b(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('Operation Request', () {
    final codec = GrBleCatalog.operationRequest.codec;

    test('documented commands', () {
      expect(codec.encode(BleOperationRequest.shutterWithAf), [1, 1]);
      expect(codec.encode(BleOperationRequest.shutterWithoutAf), [1, 0]);
      expect(codec.encode(BleOperationRequest.focusOnly), [0, 1]);
      expect(codec.encode(BleOperationRequest.greenButton), [0, 2]);
    });

    test('decode and text parse', () {
      final d = codec.decode(b([2, 1]));
      expect(d.value!.code.known, BleOperationCode.stop);
      expect(d.value!.parameter.known, BleOperationParameter.af);
      expect(codec.encodeText('start,noAf'), [1, 0]);
      expect(codec.encodeText('hex:0002'), [0, 2]);
      expect(() => codec.parse('start'), throwsFormatException);
      expect(codec.decode(b([1])).value, isNull);
    });
  });

  group('Self Timer', () {
    final codec = GrBleCatalog.selfTimer.codec;

    test('GR WORLD sends 1 byte, Image Sync 2 bytes', () {
      expect(codec.encode(BleSelfTimerCancelFormat.grWorld.command), [1]);
      expect(codec.encode(BleSelfTimerCancelFormat.imageSync.command), [1, 1]);
    });

    test('decodes both lengths', () {
      expect(codec.decode(b([1])).value!.remocon, isNull);
      expect(codec.decode(b([1, 1])).value!.remocon!.known, BleRemocon.on);
      expect(codec.decode(b([1, 1, 0])).issues, hasLength(1));
      expect(codec.decode(b([])).value, isNull);
    });
  });

  group('Shooting Mode', () {
    final codec = GrBleCatalog.shootingMode.codec;

    test('GR WORLD 2-byte form', () {
      final d = codec.decode(b([0x13, 0x01]));
      expect(d.issues, isEmpty);
      expect(d.value!.mode.known, BleExposureMode.sfp);
      expect(d.value!.userMode.known, BleUserMode.u1);
      expect(d.value!.option, isNull);
      expect(codec.encode(d.value!), [0x13, 0x01]);
    });

    test('Image Sync 3-byte form keeps its length on re-encode', () {
      final d = codec.decode(b([0x01, 0x00, 0x02]));
      expect(d.value!.option!.known, BleShootingModeOption.shift);
      final changed = d.value!.copyWith(
        mode: BleEnumValue.of(BleExposureMode.m),
      );
      expect(codec.encode(changed), [0x03, 0x00, 0x02]);
    });

    test('unknown mode stays raw; short and long input', () {
      expect(codec.decode(b([0x30, 0x00])).value!.mode.raw, 0x30);
      expect(codec.decode(b([0x01])).value, isNull);
      expect(codec.decode(b([1, 0, 0, 0])).issues, hasLength(1));
    });
  });

  group('Capture Status', () {
    final codec = GrBleCatalog.captureStatus.codec;

    test('GR WORLD 2-byte form', () {
      final d = codec.decode(b([0x01, 0x01]));
      expect(d.issues, isEmpty);
      expect(d.value!.capturing.known, BleCapturing.capturing);
      expect(d.value!.countdown.known, BleCountdown.selfTimer);
      expect(d.value!.isExtended, isFalse);
    });

    test('Image Sync 8-byte form with uint16 tracking time', () {
      final d = codec.decode(
        b([0x00, 0x02, 0x04, 0x01, 0x02, 0x01, 0x2c, 0x01]),
      );
      expect(d.issues, isEmpty);
      final v = d.value!;
      expect(v.countdown.known, BleCountdown.waitingForScheduledTime);
      expect(v.still!.known, BleStillCaptureState.interval);
      expect(v.movie!.known, BleMovieCaptureState.recording);
      expect(v.type3CaptureState!.known, BleType3CaptureState.mainCapture);
      expect(
        v.type3PreCaptureResult!.known,
        BleType3PreCaptureResult.motionNotDetectable,
      );
      expect(v.astroTrackingTime, 300);
      expect(codec.encode(v), [0, 2, 4, 1, 2, 1, 0x2c, 1]);
    });

    test('other lengths decode with an issue; too short has no value', () {
      final mid = codec.decode(b([0, 0, 0, 0, 0]));
      expect(mid.value!.isExtended, isFalse);
      expect(mid.issues, hasLength(1));
      expect(codec.decode(b([0])).value, isNull);
      expect(codec.decode(b([0, 9])).value!.countdown.raw, 9);
    });
  });

  group('Date Time', () {
    final codec = GrBleCatalog.dateTime.codec;

    test('7 bytes: year LE, month, day, hour, minute, second', () {
      final v = BleDateTime.fromDateTime(DateTime(2026, 11, 7, 12, 34, 56));
      expect(codec.encode(v), [0xea, 0x07, 11, 7, 12, 34, 56]);
      final d = codec.decode(b([0xea, 0x07, 11, 7, 12, 34, 56]));
      expect(d.value!.iso, '2026-11-07T12:34:56');
      expect(d.value!.toLocalDateTime(), DateTime(2026, 11, 7, 12, 34, 56));
    });

    test('out-of-range fields decode with issues', () {
      final d = codec.decode(b([0xea, 0x07, 13, 0, 24, 0, 0]));
      expect(d.value!.month, 13);
      expect(d.issues, hasLength(3));
      expect(d.value!.toLocalDateTime(), isNull);
    });

    test('encode rejects invalid fields; short input', () {
      expect(
        () => codec.encode(
          const BleDateTime(
            year: 2026,
            month: 0,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0,
          ),
        ),
        throwsArgumentError,
      );
      expect(codec.decode(b([0xea, 0x07, 11])).value, isNull);
    });

    test('parses ISO text as written', () {
      expect(codec.encodeText('2026-01-02T03:04:05Z'), [
        0xea,
        0x07,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(() => codec.parse('yesterday'), throwsFormatException);
    });
  });

  group('GPS Information', () {
    final codec = GrBleCatalog.gpsInformation.codec;
    final wire = b([
      0x3f, 0xf0, 0, 0, 0, 0, 0, 0, // 1.0 BE
      0xc0, 0x04, 0, 0, 0, 0, 0, 0, // -2.5 BE
      0x40, 0x59, 0, 0, 0, 0, 0, 0, // 100.0 BE
      0xea, 0x07, 11, 7, 12, 34, 56, // 2026-11-07 12:34:56
      0x00, // WGS84
    ]);

    test('float64 big-endian then LE year, 32 bytes', () {
      final record = BleGpsInformation.at(
        latitude: 1,
        longitude: -2.5,
        altitude: 100,
        time: DateTime.utc(2026, 11, 7, 12, 34, 56),
      );
      expect(codec.encode(record), wire);
      final d = codec.decode(wire);
      expect(d.issues, isEmpty);
      expect(d.value!.latitude, 1.0);
      expect(d.value!.longitude, -2.5);
      expect(d.value!.altitude, 100.0);
      expect(d.value!.datum.known, BleGpsDatum.wgs84);
    });

    test('rejects out-of-range coordinates; short input', () {
      expect(
        () => codec.encode(
          BleGpsInformation.at(
            latitude: 91,
            longitude: 0,
            altitude: 0,
            time: DateTime.utc(2026),
          ),
        ),
        throwsArgumentError,
      );
      expect(codec.decode(Uint8List.sublistView(wire, 0, 31)).value, isNull);
    });
  });

  group('Battery Level', () {
    final codec = GrBleCatalog.batteryLevel.codec;

    test('1-byte and Image Sync 2-byte forms', () {
      expect(codec.decode(b([85])).value!.level, 85);
      final two = codec.decode(b([40, 1]));
      expect(two.value!.powerSource!.known, BlePowerSource.acAdapter);
      expect(two.value!.endScreenData, isNull);
    });

    test('GR WORLD long form: len >= 130 and byte1 == 1', () {
      final bytes = Uint8List(130)
        ..[0] = 50
        ..[1] = 1
        ..[2] = 0xaa
        ..[129] = 0xbb;
      final d = codec.decode(bytes);
      expect(d.issues, isEmpty);
      expect(d.value!.endScreenData, hasLength(128));
      expect(d.value!.endScreenData!.first, 0xaa);
      expect(d.value!.endScreenData!.last, 0xbb);
      expect(d.value!.powerSource, isNull);
    });

    test('other lengths keep the level and report', () {
      final d = codec.decode(b([10, 0, 0]));
      expect(d.value!.level, 10);
      expect(d.issues, hasLength(1));
      expect(codec.decode(b([])).value, isNull);
    });
  });

  group('Storage Information', () {
    final codec = GrBleCatalog.storageInformation.codec;
    final entry14 = [
      0x01, 0x01, 0x00, 0x01, 0x01, // SD1, exists, unlocked, available, fmt
      0xe8, 0x03, 0x00, 0x00, // 1000 pictures
      0x10, 0x0e, 0x00, 0x00, // 3600 s
      0x05, // file type (unknown meaning)
    ];

    test('14-byte entries (GR WORLD, GR III)', () {
      final d = codec.decode(b([1, ...entry14]));
      expect(d.issues, isEmpty);
      expect(d.value!.entrySize, 14);
      final e = d.value!.entries.single;
      expect(e.type.known, BleStorageType.sdSlot1);
      expect(e.exists && !e.locked && e.available && e.formatted, isTrue);
      expect(e.remainingPictures, 1000);
      expect(e.remainingVideoSeconds, 3600);
      expect(e.fileType, 5);
      expect(e.active, isNull);
      expect(codec.encode(d.value!), [1, ...entry14]);
    });

    test('15-byte entries (Image Sync) with Active', () {
      final d = codec.decode(b([2, ...entry14, 1, ...entry14, 0]));
      expect(d.value!.entrySize, 15);
      expect(d.value!.entries.map((e) => e.active), [true, false]);
    });

    test('empty list and mismatched lengths', () {
      expect(codec.decode(b([0])).value!.entries, isEmpty);
      final bad = codec.decode(b([2, ...entry14]));
      expect(bad.value, isNull);
      expect(bad.issues, hasLength(1));
      expect(codec.decode(b([])).value, isNull);
    });

    test('negative remaining counts decode as sint32', () {
      final e = [...entry14]..setRange(5, 9, [0xff, 0xff, 0xff, 0xff]);
      expect(
        codec.decode(b([1, ...e])).value!.entries.single.remainingPictures,
        -1,
      );
    });
  });

  group('two-byte records', () {
    test('File Transfer List', () {
      final d = GrBleCatalog.fileTransferList.codec.decode(b([1, 0]));
      expect(d.value!.notEmpty, isTrue);
      expect(d.value!.changed, isFalse);
    });

    test('Power Off During Transfer keeps byte 0 semantics', () {
      final codec = GrBleCatalog.powerOffDuringTransfer.codec;
      final d = codec.decode(b([1, 1]));
      expect(
        d.value!.behavior.known,
        BleTransferPowerOffBehavior.powerOffAfterTransfer,
      );
      expect(d.value!.autoResize, isTrue);
      expect(codec.encodeText('abortTransferAndPowerOff,false'), [0, 0]);
    });

    test('Focus Mode, AF status, Shot Count', () {
      final focus = GrBleCatalog.focusMode.codec.decode(b([1, 10]));
      expect(focus.value!.mode.known, BleFocusMode.auto);
      expect(focus.value!.setting.known, BleFocusSetting.starAf);
      final af = GrBleCatalog.afStatus.codec.decode(b([1, 1]));
      expect(af.value!.inFocus.known, BleAfInFocus.inFocus);
      final shots = GrBleCatalog.shotCount.codec.decode(b([3, 9]));
      expect(shots.value!.current, 3);
      expect(shots.value!.total, 9);
      expect(GrBleCatalog.shotCount.codec.decode(b([3])).value, isNull);
    });

    test('File Type 4 bytes', () {
      final codec = GrBleCatalog.fileType.codec;
      final d = codec.decode(b([4, 1, 0, 2]));
      expect(d.value!.fileType.known, BleStillFileType.jpegDng);
      expect(d.value!.rawType.known, BleRawType.dng);
      expect(d.value!.slotMode.known, BleSlotMode.rawJpegSplit);
      expect(
        codec.encode(
          d.value!.copyWith(fileType: BleEnumValue.of(BleStillFileType.jpeg)),
        ),
        [0, 1, 0, 2],
      );
      expect(codec.decode(b([4, 1, 0])).value, isNull);
    });
  });

  group('Image Control blob', () {
    final codec = GrBleCatalog.imageControl1Data.codec;

    test('decodes version, base image and signed parameters', () {
      final d = codec.decode(
        b([0x02, 0x00, 0x11, 0x02, 0x03, 0xfe, 0x23, 0x01]),
      );
      expect(d.issues, isEmpty);
      final v = d.value!;
      expect(v.version, 2);
      expect(v.base.known, BleImageControlBase.standardMono);
      expect(
        v.parameters[0].parameter.known,
        BleImageControlParameter.contrast,
      );
      expect(v.parameters[0].value, -2);
      expect(
        v.parameters[1].parameter.known,
        BleImageControlParameter.solarizationType,
      );
      expect(codec.encode(v), [0x02, 0x00, 0x11, 0x02, 0x03, 0xfe, 0x23, 0x01]);
    });

    test('unsupported version, unknown ids, truncation and trailing bytes', () {
      final d = codec.decode(b([0x03, 0x00, 0x0a, 0x02, 0x40, 0x01]));
      expect(d.value!.parameters.single.parameter.raw, 0x40);
      expect(d.value!.base.known, isNull);
      expect(d.issues, hasLength(2));
      final trailing = codec.decode(b([0x01, 0x00, 0x00, 0x00, 0x99]));
      expect(trailing.value!.trailing, [0x99]);
      expect(codec.encode(trailing.value!), [0x01, 0x00, 0x00, 0x00, 0x99]);
      expect(codec.decode(b([1, 0, 0])).value, isNull);
    });
  });

  group('paired device name sanitiser', () {
    test('GR WORLD rules', () {
      expect(GrBleClient.sanitizePairedDeviceName('  Pixel 9 '), 'Pixel 9');
      expect(GrBleClient.sanitizePairedDeviceName('Café'), 'Caf?');
      expect(GrBleClient.sanitizePairedDeviceName('a\u3000b'), 'a\u3000b');
      expect(GrBleClient.sanitizePairedDeviceName(''), 'Unknown');
      expect(GrBleClient.sanitizePairedDeviceName('x' * 40), 'x' * 32);
    });
  });
}
