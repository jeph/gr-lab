import 'dart:convert';
import 'dart:typed_data';

/// `FF <marker> <len16> payload` with the length covering itself.
List<int> segment(int marker, List<int> payload) => [
  0xFF,
  marker,
  (payload.length + 2) >> 8,
  (payload.length + 2) & 0xFF,
  ...payload,
];

/// A structurally valid JPEG: SOI, APP0, optional APP1, SOFn, SOS, entropy
/// data (with a stuffed `FF 00` and an `FF D3` restart marker by default),
/// EOI.
Uint8List jpeg({
  int width = 720,
  int height = 480,
  int sof = 0xC0,
  List<int>? app1,
  List<int> entropy = const [1, 2, 3, 0xFF, 0x00, 4, 0xFF, 0xD3, 5, 6],
}) => Uint8List.fromList([
  0xFF,
  0xD8,
  ...segment(0xE0, [0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
  if (app1 != null) ...segment(0xE1, app1),
  ...segment(sof, [
    8,
    height >> 8,
    height & 0xFF,
    width >> 8,
    width & 0xFF,
    3,
    1,
    0x22,
    0,
    2,
    0x11,
    1,
    3,
    0x11,
    1,
  ]),
  ...segment(0xDA, [3, 1, 0, 2, 0x11, 3, 0x11, 0, 63, 0]),
  ...entropy,
  0xFF,
  0xD9,
]);

/// The part header the firmware sends before each frame
/// (research/protocol/remote-shooting.md §1.2).
final List<int> partHeader = ascii.encode(
  '--boundary\r\nContent-Type: image/jpeg\r\n\r\n',
);

/// The firmware's response head (remote-shooting.md §1.2).
final List<int> responseHead = ascii.encode(
  'HTTP/1.1 200 OK\r\n'
  'Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n'
  'Expires: 0\r\n'
  'Pragma: no-cache\r\n'
  'Content-Type: multipart/x-mixed-replace; boundary=--boundary\r\n\r\n',
);
