import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Output of [MjpegSplitter.add].
sealed class MjpegEvent {
  const new();
}

/// A complete JPEG, SOI (`FF D8`) through EOI (`FF D9`) inclusive.
final class MjpegFrame extends MjpegEvent {
  /// Frame [jpeg] preceded by [partHeader].
  const new(this.jpeg, {this.partHeader = ''});

  /// The JPEG bytes, SOI through EOI.
  final Uint8List jpeg;

  /// The text between the previous frame and this one (boundary line and
  /// part headers), trimmed; at most [MjpegSplitter.maxPartHeaderBytes].
  final String partHeader;
}

/// Why [MjpegSplitter] discarded a partial frame.
enum MjpegDropReason {
  /// The frame grew past [MjpegSplitter.maxFrameBytes] without an EOI.
  tooLarge,

  /// A new SOI marker appeared before the current frame's EOI (truncated
  /// frame on the wire).
  interrupted,
}

/// Bytes of a partial frame that were discarded.
final class MjpegDropped extends MjpegEvent {
  /// [bytes] of a partial frame dropped for [reason].
  const new(this.reason, this.bytes);

  /// Why the frame was dropped.
  final MjpegDropReason reason;

  /// Bytes discarded.
  final int bytes;
}

enum _S { seek, expectFF, markerCode, lenHi, lenLo, skip, entropy }

/// Marker-driven JPEG splitter for the camera's live-view stream.
///
/// The firmware declares `boundary=--boundary` but delimits parts with
/// `--boundary`, and sends no per-part Content-Length, so a strict multipart
/// parser fails (docs/protocol/remote-shooting.md §1.2). Like Image Sync's
/// `MjpegInputStream`, this ignores the multipart framing entirely and finds
/// frames by JPEG markers. Unlike Image Sync's blind `FF D9` search it walks
/// the JPEG segment structure (length-prefixed headers, byte-stuffed entropy
/// data), so an `FF D9` inside an embedded EXIF thumbnail does not end the
/// frame early, and it never appends the next part's header to a frame.
///
/// Bytes outside frames (part headers, boundaries, garbage) are counted in
/// [interFrameBytes]. Input may be split anywhere. Never throws.
final class MjpegSplitter {
  /// Splitter that drops frames longer than [maxFrameBytes] (≥ 4).
  new({this.maxFrameBytes = defaultMaxFrameBytes}) {
    if (maxFrameBytes < 4) {
      throw ArgumentError.value(maxFrameBytes, 'maxFrameBytes', 'must be ≥ 4');
    }
  }

  /// Image Sync caps frames at 200 000 bytes (remote-shooting.md §1.2 item 5).
  /// The default is higher because `reso=` may request larger frames than the
  /// 720×480 default Image Sync streams.
  static const int defaultMaxFrameBytes = 1024 * 1024;

  /// How much of the bytes between frames [MjpegFrame.partHeader] keeps.
  static const maxPartHeaderBytes = 1024;

  /// Largest frame kept; a longer one is dropped as
  /// [MjpegDropReason.tooLarge].
  final int maxFrameBytes;

  _S _state = _S.seek;
  bool _seekFF = false;
  bool _entropyFF = false;
  bool _segmentIsSos = false;
  int _segmentLength = 0;
  int _remaining = 0;
  Uint8List _buf = Uint8List(64 * 1024);
  int _len = 0;
  final BytesBuilder _between = BytesBuilder();

  /// Bytes seen outside any frame, including discarded partial frames.
  int interFrameBytes = 0;

  /// Bytes buffered for the frame in progress.
  int get pendingBytes => _len;

  /// Feeds [chunk] and returns the frames (and drops) it completed, in order.
  List<MjpegEvent> add(List<int> chunk) {
    final out = <MjpegEvent>[];
    var i = 0;
    final n = chunk.length;
    while (i < n) {
      switch (_state) {
        case _S.seek:
          final b = chunk[i++];
          if (_seekFF && b == 0xD8) {
            interFrameBytes--; // the FF just counted belongs to the SOI
            _seekFF = false;
            _startFrame();
          } else {
            interFrameBytes++;
            // The FF of an SOI is held back until the next byte decides.
            if (_seekFF) _keepBetween(0xFF);
            _seekFF = b == 0xFF;
            if (!_seekFF) _keepBetween(b);
          }
        case _S.expectFF:
          final b = chunk[i++];
          if (!_append(b, out)) continue;
          // A non-marker byte where a marker must be: fall back to scanning
          // for EOI, as Image Sync does.
          _state = b == 0xFF ? _S.markerCode : _S.entropy;
        case _S.markerCode:
          _marker(chunk[i++], out);
        case _S.lenHi:
          final b = chunk[i++];
          if (!_append(b, out)) continue;
          _segmentLength = b << 8;
          _state = _S.lenLo;
        case _S.lenLo:
          final b = chunk[i++];
          if (!_append(b, out)) continue;
          final length = _segmentLength | b;
          if (length < 2) {
            _state = _S.entropy;
          } else {
            _remaining = length - 2;
            _state = _remaining == 0 ? _afterSegment : _S.skip;
          }
        case _S.skip:
          final take = math.min(_remaining, n - i);
          if (!_appendRange(chunk, i, i + take, out)) {
            i += take;
            continue;
          }
          i += take;
          _remaining -= take;
          if (_remaining == 0) _state = _afterSegment;
        case _S.entropy:
          if (_entropyFF) {
            _entropyFF = false;
            final b = chunk[i++];
            if (b == 0x00 || (b >= 0xD0 && b <= 0xD7)) {
              _append(b, out);
            } else if (b == 0xFF) {
              if (_append(b, out)) _entropyFF = true;
            } else {
              _marker(b, out);
            }
          } else {
            var j = i;
            while (j < n && chunk[j] != 0xFF) {
              j++;
            }
            final end = j < n ? j + 1 : n;
            if (_appendRange(chunk, i, end, out) && j < n) _entropyFF = true;
            i = end;
          }
      }
    }
    return out;
  }

  /// Discards any partial frame and returns to scanning for SOI.
  void reset() {
    interFrameBytes += _len;
    _len = 0;
    _state = _S.seek;
    _seekFF = false;
    _entropyFF = false;
    _between.clear();
  }

  void _keepBetween(int b) {
    if (_between.length < maxPartHeaderBytes) _between.addByte(b);
  }

  _S get _afterSegment => _segmentIsSos ? _S.entropy : _S.expectFF;

  void _startFrame() {
    _len = 0;
    _put(0xFF);
    _put(0xD8);
    _state = _S.expectFF;
    _entropyFF = false;
  }

  /// Handles the byte after an `FF` that starts a marker.
  void _marker(int code, List<MjpegEvent> out) {
    if (code == 0xD8) {
      final dropped = _len - 1; // the FF just appended starts the new SOI
      interFrameBytes += dropped;
      out.add(MjpegDropped(MjpegDropReason.interrupted, dropped));
      _startFrame();
      return;
    }
    if (!_append(code, out)) return;
    switch (code) {
      case 0xD9:
        out.add(
          MjpegFrame(
            Uint8List.fromList(Uint8List.sublistView(_buf, 0, _len)),
            partHeader: latin1.decode(_between.takeBytes()).trim(),
          ),
        );
        _len = 0;
        _state = _S.seek;
        _seekFF = false;
      case 0xFF:
        _state = _S.markerCode;
      case 0x01:
      case >= 0xD0 && <= 0xD7:
        _state = _S.expectFF;
      case 0x00:
        _state = _S.entropy;
      default:
        _segmentIsSos = code == 0xDA;
        _state = _S.lenHi;
    }
  }

  bool _append(int b, List<MjpegEvent> out) {
    if (_len + 1 > maxFrameBytes) {
      _overflow(1, out);
      return false;
    }
    _put(b);
    return true;
  }

  bool _appendRange(List<int> src, int start, int end, List<MjpegEvent> out) {
    final count = end - start;
    if (_len + count > maxFrameBytes) {
      _overflow(count, out);
      return false;
    }
    _ensure(_len + count);
    _buf.setRange(_len, _len + count, src, start);
    _len += count;
    return true;
  }

  void _put(int b) {
    _ensure(_len + 1);
    _buf[_len++] = b;
  }

  void _ensure(int capacity) {
    if (capacity <= _buf.length) return;
    var size = _buf.length * 2;
    while (size < capacity) {
      size *= 2;
    }
    _buf = Uint8List(size)..setRange(0, _len, _buf);
  }

  void _overflow(int attempted, List<MjpegEvent> out) {
    final dropped = _len + attempted;
    out.add(MjpegDropped(MjpegDropReason.tooLarge, dropped));
    interFrameBytes += dropped;
    _len = 0;
    _state = _S.seek;
    _seekFF = false;
    _entropyFF = false;
  }
}

/// Image size read from a JPEG start-of-frame segment.
final class JpegDimensions {
  /// Size [width] × [height] from SOF marker [sofMarker].
  const new(this.width, this.height, this.sofMarker);

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// `0xC0` baseline, `0xC2` progressive, other SOFn values as found.
  final int sofMarker;

  /// Whether the image is progressive (SOF2).
  bool get progressive => sofMarker == 0xC2;

  @override
  String toString() => '${width}x$height';
}

/// Reads width/height from the first SOFn segment (SOF0, SOF2 and the other
/// SOF variants; not DHT `C4`, JPG `C8` or DAC `CC`). Returns `null` for
/// data that is not a JPEG or ends before an SOF. Never throws.
JpegDimensions? readJpegDimensions(List<int> jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return null;
  var p = 2;
  while (p < jpeg.length) {
    if (jpeg[p] != 0xFF) return null;
    while (p < jpeg.length && jpeg[p] == 0xFF) {
      p++;
    }
    if (p >= jpeg.length) return null;
    final m = jpeg[p++];
    if (m == 0xD9 || m == 0xDA) return null;
    if (m == 0x01 || (m >= 0xD0 && m <= 0xD7)) continue;
    if (p + 2 > jpeg.length) return null;
    final length = (jpeg[p] << 8) | jpeg[p + 1];
    if (length < 2) return null;
    final isSof = m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC;
    if (isSof) {
      if (length < 7 || p + 7 > jpeg.length) return null;
      final height = (jpeg[p + 3] << 8) | jpeg[p + 4];
      final width = (jpeg[p + 5] << 8) | jpeg[p + 6];
      return JpegDimensions(width, height, m);
    }
    p += length;
  }
  return null;
}

/// Incremental HTTP/1.1 `Transfer-Encoding: chunked` decoder for the raw
/// live-view socket. Malformed framing sets [error] and ignores further
/// input; it never throws.
final class HttpChunkedDecoder {
  static const _maxLine = 4096;

  // 0 size line, 1 data, 2 CRLF after data, 3 trailer lines, 4 done.
  int _state = 0;
  final List<int> _line = [];
  int _remaining = 0;

  /// Set when the framing is malformed.
  String? error;

  /// The terminating zero-size chunk and trailer were read.
  bool get done => _state == 4;

  /// Returns the payload bytes contained in [input].
  Uint8List add(List<int> input) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < input.length && error == null && _state != 4) {
      switch (_state) {
        case 0 || 3:
          final b = input[i++];
          if (b != 0x0A) {
            if (_line.length >= _maxLine) {
              error = 'chunk header line too long';
            } else {
              _line.add(b);
            }
            continue;
          }
          final text = String.fromCharCodes(_line).replaceAll('\r', '');
          _line.clear();
          if (_state == 3) {
            if (text.isEmpty) _state = 4;
            continue;
          }
          final sizeText = text.split(';').first.trim();
          final size = RegExp(r'^[0-9A-Fa-f]{1,8}$').hasMatch(sizeText)
              ? int.parse(sizeText, radix: 16)
              : null;
          if (size == null) {
            error = 'invalid chunk size line "$text"';
          } else if (size == 0) {
            _state = 3;
          } else {
            _remaining = size;
            _state = 1;
          }
        case 1:
          final take = math.min(_remaining, input.length - i);
          out.add(
            input is Uint8List
                ? Uint8List.sublistView(input, i, i + take)
                : input.sublist(i, i + take),
          );
          i += take;
          _remaining -= take;
          if (_remaining == 0) _state = 2;
        case 2:
          final b = input[i++];
          if (b == 0x0D) continue;
          if (b == 0x0A) {
            _state = 0;
          } else {
            error = 'missing CRLF after chunk data';
          }
      }
    }
    return out.takeBytes();
  }
}
