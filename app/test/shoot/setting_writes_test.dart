import 'package:flutter_test/flutter_test.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/shoot/setting_writes.dart';

/// The camera's settings: `av` and `tv` with their lists.
GrProps _props({String av = '2.8', String tv = '1/250', bool lists = true}) =>
    GrProps({
      'av': av,
      'tv': tv,
      if (lists) 'avList': ['2.8', '4.0', '5.6'],
      if (lists) 'tvList': ['1/250', '1/500'],
      if (lists) 'effectList': ['off', 'efc_monochrome'],
    });

/// The answer to a change: current values, no `CameraConstants` lists.
GrProps _answer({String av = '2.8', String tv = '1/250'}) =>
    _props(av: av, tv: tv, lists: false);

SettingWrites _read() {
  final s = SettingWrites();
  return s..read(_props(), since: s.startRead());
}

void main() {
  test('a change shows at once and its answer keeps the lists', () {
    final s = _read();
    final a = s.begin('av', '4.0');
    expect(s.props!.raw['av'], '4.0');
    s.succeeded(a, 'av', _answer(av: '4.0'));
    expect(s.props!.raw['av'], '4.0');
    expect(s.props!.raw['effectList'], ['off', 'efc_monochrome']);
  });

  test('a failure after a newer change succeeded keeps the newer one', () {
    final s = _read();
    final a = s.begin('av', '4.0');
    final b = s.begin('tv', '1/500');
    s.succeeded(b, 'tv', _answer(tv: '1/500'));
    s.failed(a, 'av');
    expect(s.props!.raw['av'], '2.8');
    expect(s.props!.raw['tv'], '1/500');
  });

  test('an older answer arriving last does not undo a newer one', () {
    final s = _read();
    final a = s.begin('av', '4.0');
    final b = s.begin('av', '5.6');
    s.succeeded(b, 'av', _answer(av: '5.6'));
    s.succeeded(a, 'av', _answer(av: '4.0'));
    expect(s.props!.raw['av'], '5.6');
  });

  test('an answer settles older waiting changes of its key', () {
    final s = _read();
    final a = s.begin('av', '4.0');
    final b = s.begin('av', '5.6');
    s.succeeded(b, 'av', _answer(av: '5.6'));
    expect(s.props!.raw['av'], '5.6');
    s.failed(a, 'av');
    expect(s.props!.raw['av'], '5.6');
  });

  test('an older answer while a newer change waits shows the newer', () {
    final s = _read();
    final a = s.begin('av', '4.0');
    final b = s.begin('tv', '1/500');
    s.succeeded(a, 'av', _answer(av: '4.0'));
    expect(s.props!.raw['tv'], '1/500');
    s.failed(b, 'tv');
    expect(s.props!.raw['av'], '4.0');
    expect(s.props!.raw['tv'], '1/250');
  });

  test('two failed changes of one key show what the camera has', () {
    final s = _read();
    final a = s.begin('av', '4.0');
    final b = s.begin('av', '5.6');
    expect(s.props!.raw['av'], '5.6');
    s.failed(b, 'av');
    expect(s.props!.raw['av'], '4.0', reason: 'still waiting for 4.0');
    s.failed(a, 'av');
    expect(s.props!.raw['av'], '2.8');
  });

  test('a read started before an answer is dropped', () {
    final s = _read();
    final since = s.startRead();
    final a = s.begin('av', '4.0');
    s.succeeded(a, 'av', _answer(av: '4.0'));
    s.read(_props(), since: since);
    expect(s.props!.raw['av'], '4.0');
  });

  test(
    'a read started while a change waits is dropped once it is answered',
    () {
      final s = _read();
      final a = s.begin('av', '4.0');
      final since = s.startRead();
      s.succeeded(a, 'av', _answer(av: '4.0'));
      s.read(_props(), since: since);
      expect(s.props!.raw['av'], '4.0');
    },
  );

  test('a read keeps the changes still waiting', () {
    final s = _read();
    s.begin('av', '4.0');
    s.read(_props(tv: '1/500'), since: s.startRead());
    expect(s.props!.raw['av'], '4.0');
    expect(s.props!.raw['tv'], '1/500');
  });

  test('a read started before one already used is dropped', () {
    final s = _read();
    final older = s.startRead();
    final newer = s.startRead();
    s.read(_props(tv: '1/500'), since: newer);
    s.read(_props(), since: older);
    expect(s.props!.raw['tv'], '1/500');
    expect(s.props!.raw['tvList'], ['1/250', '1/500']);
  });

  test('reads that arrive in order are all used', () {
    final s = _read();
    final first = s.startRead();
    final second = s.startRead();
    s.read(_props(tv: '1/500'), since: first);
    expect(s.props!.raw['tv'], '1/500');
    s.read(_props(av: '4.0'), since: second);
    expect(s.props!.raw['av'], '4.0');
  });

  test('after the mode dial moves, only a read started later settles it', () {
    final s = _read();
    expect(s.modeSettled, isTrue);
    final before = s.startRead();
    s.modeChanged();
    expect(s.modeSettled, isFalse);
    s.read(_props(tv: '1/500'), since: before);
    expect(s.modeSettled, isFalse, reason: 'started in the old mode');
    s.read(_props(), since: s.startRead());
    expect(s.modeSettled, isTrue);
  });

  test('an answer from before the mode dial moved does not replace the '
      'settings read for the new mode', () {
    final s = _read();
    final a = s.begin('tv', '1/500');
    s.modeChanged();
    // The camera, now in Av, sets the shutter speed itself.
    s.read(
      GrProps({
        'av': '2.8',
        'tv': '1/250',
        'tvList': ['1/250'],
      }),
      since: s.startRead(),
    );
    // Answered in M, before the dial moved, but arriving last.
    s.succeeded(
      a,
      'tv',
      GrProps({
        'av': '2.8',
        'tv': '1/500',
        'tvList': ['1/250', '1/500'],
      }),
    );
    expect(s.modeSettled, isTrue);
    expect(s.props!.raw['tv'], '1/250');
    expect(s.props!.raw['tvList'], ['1/250']);
  });

  test('an answer from before the mode dial moved is used until a read for '
      'the new mode is in', () {
    final s = _read();
    final a = s.begin('tv', '1/500');
    s.modeChanged();
    s.succeeded(a, 'tv', _answer(tv: '1/500'));
    expect(s.props!.raw['tv'], '1/500');
    expect(s.modeSettled, isFalse);
  });

  test('results from before clear are dropped', () {
    final s = _read();
    final since = s.startRead();
    final a = s.begin('av', '4.0');
    s.clear();
    s.succeeded(a, 'av', _answer(av: '4.0'));
    s.read(_props(), since: since);
    expect(s.props, isNull);
  });
}
