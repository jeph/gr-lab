import 'dart:convert';
import 'dart:typed_data';

import 'package:gr_protocol/src/http/http.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

List<Uint8List> framesOf(List<MjpegEvent> events) => [
  for (final e in events)
    if (e is MjpegFrame) e.jpeg,
];

List<MjpegEvent> feed(MjpegSplitter s, List<int> bytes, List<int> cuts) {
  final out = <MjpegEvent>[];
  var start = 0;
  for (final cut in [...cuts, bytes.length]) {
    out.addAll(s.add(bytes.sublist(start, cut)));
    start = cut;
  }
  return out;
}

void main() {
  group('MjpegSplitter', () {
    final a = jpeg();
    final b = jpeg(width: 640, height: 360, entropy: [9, 8, 7]);
    final stream = [
      ...partHeader, ...a, 0x0D, 0x0A, //
      ...partHeader, ...b, 0x0D, 0x0A,
    ];

    test('splits firmware parts by markers, ignoring the boundary', () {
      final s = MjpegSplitter();
      final frames = framesOf(s.add(stream));
      expect(frames, [a, b]);
      expect(s.interFrameBytes, partHeader.length * 2 + 4);
      expect(s.pendingBytes, 0);
    });

    test('same frames for every two-chunk split point', () {
      for (var cut = 0; cut <= stream.length; cut++) {
        final frames = framesOf(feed(MjpegSplitter(), stream, [cut]));
        expect(frames, [a, b], reason: 'cut at $cut');
      }
    });

    test('same frames when fed one byte at a time', () {
      final s = MjpegSplitter();
      final cuts = [for (var i = 1; i < stream.length; i++) i];
      expect(framesOf(feed(s, stream, cuts)), [a, b]);
    });

    test('skips garbage, stray FF bytes and a missing part header', () {
      final noisy = [
        0x00,
        0xFF,
        0x12,
        0xFF,
        0xFF,
        ...utf8.encode('junk\r\n'),
        ...a,
        0xFF,
        0xD9,
        0xFF,
        ...b,
      ];
      expect(framesOf(MjpegSplitter().add(noisy)), [a, b]);
    });

    test('an EOI inside an APP1 thumbnail does not end the frame', () {
      final thumb = jpeg(width: 160, height: 120);
      final withExif = jpeg(app1: [...ascii.encode('Exif'), 0, 0, ...thumb]);
      final frames = framesOf(
        MjpegSplitter().add([...partHeader, ...withExif]),
      );
      expect(frames, [withExif]);
      expect(readJpegDimensions(frames.single)!.width, 720);
    });

    test(
      'byte-stuffed FF00, restart markers and fill bytes stay in the frame',
      () {
        final f = jpeg(entropy: [0xFF, 0x00, 0xFF, 0xD0, 0xFF, 0xD7, 0x55]);
        expect(framesOf(MjpegSplitter().add(f)), [f]);
      },
    );

    test('a new SOI before EOI drops the truncated frame', () {
      final truncated = a.sublist(0, a.length - 6);
      final events = MjpegSplitter().add([...truncated, ...b]);
      expect(events, hasLength(2));
      final drop = events.first as MjpegDropped;
      expect(drop.reason, MjpegDropReason.interrupted);
      expect(drop.bytes, truncated.length);
      expect((events.last as MjpegFrame).jpeg, b);
    });

    test('frame over the cap is dropped and the next frame still parses', () {
      final big = jpeg(entropy: List.filled(500, 0x11));
      final s = MjpegSplitter(maxFrameBytes: big.length - 1);
      final events = s.add([...big, ...a]);
      expect(events.first, isA<MjpegDropped>());
      expect((events.first as MjpegDropped).reason, MjpegDropReason.tooLarge);
      expect(framesOf(events), [a]);
    });

    test('frame exactly at the cap is delivered', () {
      final s = MjpegSplitter(maxFrameBytes: a.length);
      expect(framesOf(s.add(a)), [a]);
    });

    test('non-marker data after SOI falls back to scanning for EOI', () {
      final odd = [0xFF, 0xD8, 0x01, 0x02, 0xFF, 0x00, 0x03, 0xFF, 0xD9];
      expect(framesOf(MjpegSplitter().add(odd)), [odd]);
    });

    test('incomplete frame stays pending until more data', () {
      final s = MjpegSplitter();
      expect(s.add(a.sublist(0, 30)), isEmpty);
      expect(s.pendingBytes, 30);
      expect(framesOf(s.add(a.sublist(30))), [a]);
    });

    test('rejects a cap below a minimal JPEG', () {
      expect(() => MjpegSplitter(maxFrameBytes: 3), throwsArgumentError);
    });
  });

  group('readJpegDimensions', () {
    test('reads SOF0 baseline', () {
      final d = readJpegDimensions(jpeg())!;
      expect(
        (d.width, d.height, d.sofMarker, d.progressive),
        (720, 480, 0xC0, false),
      );
    });

    test('reads SOF2 progressive', () {
      final d = readJpegDimensions(jpeg(width: 1920, height: 1080, sof: 0xC2))!;
      expect((d.width, d.height, d.progressive), (1920, 1080, true));
    });

    test('null for non-JPEG, truncated header or SOS before SOF', () {
      expect(readJpegDimensions([0x00, 0x01, 0x02, 0x03]), isNull);
      expect(readJpegDimensions(jpeg().sublist(0, 25)), isNull);
      expect(
        readJpegDimensions([
          0xFF,
          0xD8,
          ...segment(0xDA, [0]),
          0xFF,
          0xD9,
        ]),
        isNull,
      );
      expect(readJpegDimensions(const []), isNull);
    });
  });

  group('HttpChunkedDecoder', () {
    final encoded = ascii.encode(
      '5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\nTrailer: x\r\n\r\n',
    );

    test('decodes chunks with extensions and trailer', () {
      final d = HttpChunkedDecoder();
      expect(ascii.decode(d.add(encoded)), 'hello world');
      expect(d.done, isTrue);
      expect(d.error, isNull);
    });

    test('decodes input split at every position', () {
      for (var cut = 0; cut <= encoded.length; cut++) {
        final d = HttpChunkedDecoder();
        final text = ascii.decode([
          ...d.add(encoded.sublist(0, cut)),
          ...d.add(encoded.sublist(cut)),
        ]);
        expect(text, 'hello world', reason: 'cut at $cut');
        expect(d.done, isTrue);
      }
    });

    test('accepts bare LF line endings', () {
      final d = HttpChunkedDecoder();
      expect(ascii.decode(d.add(ascii.encode('3\nabc\n0\n\n'))), 'abc');
      expect(d.done, isTrue);
    });

    test('flags an invalid size line and ignores later input', () {
      final d = HttpChunkedDecoder()..add(ascii.encode('zz\r\nabc'));
      expect(d.error, contains('invalid chunk size'));
      expect(d.add(ascii.encode('3\r\nabc\r\n')), isEmpty);
    });

    test('flags missing CRLF after chunk data', () {
      final d = HttpChunkedDecoder()..add(ascii.encode('3\r\nabcX'));
      expect(d.error, contains('CRLF'));
    });
  });
}
