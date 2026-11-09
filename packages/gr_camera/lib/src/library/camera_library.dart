import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// The photos of one camera over one verified Wi-Fi link: listing, file
/// info, storage-change notices and transfers. A `CameraSession` gives a
/// new one each time its Wi-Fi comes up (`CameraSession.library`), so work
/// begun on a link that has since gone is told apart with `identical`.
final class CameraLibrary {
  new _(
    this._http, {
    required this.serial,
    required this.storages,
    required this._changes,
    required this._checkWifi,
    required this._event,
  });

  /// A library over [http] directly, without a session: for tests that
  /// drive a simulated camera's HTTP server. [changes] stands for the
  /// session's `/v1/changes` socket and [checkWifi] for its Wi-Fi check
  /// (without one the camera counts as answering). Camera-layer decisions
  /// go to [trace].
  @visibleForTesting
  factory overHttp(
    GrHttpClient http, {
    required String serial,
    List<String?> storages = const [null],
    Stream<GrChangeEvent>? changes,
    Future<bool> Function()? checkWifi,
    TraceSink? trace,
  }) => CameraLibrary._(
    http,
    serial: serial,
    storages: storages,
    changes: () => changes,
    checkWifi: checkWifi,
    event: (kind, fields) => trace?.call(
      TraceEvent(
        channel: TraceChannel.session,
        direction: TraceDirection.internal,
        kind: kind,
        fields: fields,
      ),
    ),
  );

  final GrHttpClient _http;
  final Stream<GrChangeEvent>? Function() _changes;
  final Future<bool> Function()? _checkWifi;
  final void Function(String kind, Map<String, Object?> fields) _event;

  /// The paired camera's serial number.
  final String serial;

  /// Storages to list: `in` and `sd1` on a two-storage camera, a single
  /// null (no `storage=` parameter) on a camera with one.
  final List<String?> storages;

  /// Emits when the camera's `/v1/changes` socket reports a storage change
  /// (a shot taken or deleted). Empty when the socket is not open.
  Stream<void> get storageChanges =>
      _changes()?.where((e) => e is GrStorageChange) ?? const Stream.empty();

  /// Lists every file on [storages], in the camera's order. A storage that
  /// answers with an error (no card) is left out while another one lists;
  /// the error is thrown when none does. [reason] says why the listing is
  /// read (`connected`, `storageChange`, `user`), for the trace.
  Future<List<CameraFile>> listFiles({String reason = 'request'}) async {
    _event('library.list', {'reason': reason, 'storages': storages});
    final files = <CameraFile>[];
    GrApiException? failure;
    var listed = 0;
    for (final storage in storages) {
      final found = <CameraFile>[];
      try {
        await for (final page in _http.photoPages(storage: storage)) {
          for (final p in page.paths) {
            found.add(CameraFile(storage, p));
          }
        }
        files.addAll(found);
        listed++;
      } on GrApiException catch (e) {
        // A storage without a card answers with an error; the other one
        // still lists.
        _event('library.storageSkipped', {'storage': storage, 'error': '$e'});
        failure = e;
      }
    }
    if (listed == 0 && failure != null) throw failure;
    _event('library.listed', {'reason': reason, 'files': files.length});
    return files;
  }

  /// The camera's `/info` for [f].
  Future<FileInfo> fileInfo(CameraFile f) async =>
      fileInfoOf(await _http.photoInfo(f.path, storage: f.storage));

  /// A request failed ([after] says which): asks the camera once whether
  /// its Wi-Fi still works. When it does not, the session counts the link
  /// as lost and recovers it (the app leaves the camera's pages). True
  /// while the camera answers.
  Future<bool> checkWifi({required String after}) async {
    final check = _checkWifi;
    final answers = check == null || await check();
    _event('library.checkWifi', {'after': after, 'answers': answers});
    return answers;
  }

  /// Copies [f] into [file], via `<file>.part` so [file] appears only when
  /// complete. [onProgress] gets the bytes received and the camera's
  /// length (null while unknown); throwing from it stops the transfer.
  Future<void> downloadFile(
    CameraFile f,
    File file, {
    void Function(int received, int? total)? onProgress,
  }) => _http.downloadToFile(
    f.path,
    file,
    storage: f.storage,
    onProgress: onProgress,
  );

  /// Copies [files] one at a time into [dir] under their camera names and
  /// returns the copies. A file already in [dir] (finished before a pause)
  /// is kept; only an interrupted one starts over, as the camera has no
  /// ranged downloads.
  ///
  /// [onProgress] gets the bytes of all files so far, the index of the
  /// file being copied, and that file's received bytes and length.
  /// [afterFile] runs after each file. Throwing from either stops the
  /// transfer with that error.
  Future<List<File>> downloadFiles(
    List<CameraFile> files,
    Directory dir, {
    required void Function(int bytes, int index, int received, int? total)
    onProgress,
    void Function()? afterFile,
  }) async {
    await dir.create(recursive: true);
    final local = <File>[];
    var before = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final out = File('${dir.path}/${f.name}');
      // A file finished before a pause stays; only the interrupted one
      // starts over.
      if (out.existsSync()) {
        _event('download.kept', {'file': '$f', 'path': out.path});
      } else {
        await downloadFile(
          f,
          out,
          onProgress: (received, total) =>
              onProgress(before + received, i, received, total),
        );
      }
      afterFile?.call();
      before += await out.length();
      local.add(out);
    }
    return local;
  }
}

/// What this package's own classes read from a [CameraLibrary]. Not
/// exported.
extension LibraryInternals on CameraLibrary {
  /// The camera's HTTP client.
  GrHttpClient get http => _http;

  /// Records one camera-layer decision on [TraceChannel.session].
  void event(String kind, [Map<String, Object?> fields = const {}]) =>
      _event(kind, fields);
}

/// Builds a session's library; see [CameraLibrary].
CameraLibrary newCameraLibrary(
  GrHttpClient http, {
  required String serial,
  required GrProps? props,
  required Stream<GrChangeEvent>? Function() changes,
  required Future<bool> Function() checkWifi,
  required void Function(String kind, Map<String, Object?> fields) event,
}) => CameraLibrary._(
  http,
  serial: serial,
  storages: listedStorages(props),
  changes: changes,
  checkWifi: checkWifi,
  event: event,
);

/// Which storages to list, from `/v1/props`. GR WORLD adds `storage=` only
/// on cameras with two storages (http-api.md "Storage values"); a GR IV
/// lists only the SD card without it, so each equipped storage is listed on
/// its own.
List<String?> listedStorages(GrProps? props) {
  final storages = props?.storages ?? const <GrStorageInfo>[];
  if (storages.length < 2) return const [null];
  final names = [
    for (final s in storages)
      if (s.name case final name? when s.equipped != false) name,
  ];
  return names.isEmpty ? const [null] : names;
}

/// The error means the link to the camera broke (no answer, a reset
/// socket, a body cut short), rather than the camera refusing.
bool isConnectionError(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is TimeoutException ||
    error is GrMalformedResponseException;

/// Why a transfer from the camera failed. The app puts it into words; the
/// fields carry the technical detail it may show.
sealed class TransferFailure {
  const new();

  /// What [error], thrown by [CameraLibrary.downloadFile] or
  /// [CameraLibrary.downloadFiles], says about the transfer.
  factory of(Object error) => switch (error) {
    GrApiException(:final errCode, :final errMsg) => TransferRefused(
      errCode: errCode,
      errMsg: errMsg,
    ),
    GrHttpStatusException(httpStatus: final int status) => TransferHttpStatus(
      status,
    ),
    GrMalformedResponseException() => const TransferCutOff(),
    SocketException() || HttpException() => const TransferConnectionLost(),
    TimeoutException() => const TransferStalled(),
    FileSystemException(:final message, :final osError) => TransferWriteFailed(
      osError?.message ?? message,
    ),
    _ => TransferOtherError('$error'),
  };
}

/// The camera answered with an error envelope instead of the file.
final class TransferRefused extends TransferFailure {
  /// The camera refused with [errCode] and, when it sent one, [errMsg].
  const new({required this.errCode, this.errMsg});

  /// The camera's `errCode`, e.g. 404.
  final int errCode;

  /// The camera's `errMsg`, e.g. `Not Found`, as the camera sent it.
  final String? errMsg;
}

/// The camera answered a non-200 HTTP status without an error envelope.
final class TransferHttpStatus extends TransferFailure {
  /// The camera answered [httpStatus].
  const new(this.httpStatus);

  /// The HTTP status code.
  final int httpStatus;
}

/// The file arrived shorter than the camera announced.
final class TransferCutOff extends TransferFailure {
  /// The file was cut short.
  const new();
}

/// The connection to the camera broke (a reset or closed socket).
final class TransferConnectionLost extends TransferFailure {
  /// The connection broke.
  const new();
}

/// The camera stopped sending before the file was complete.
final class TransferStalled extends TransferFailure {
  /// The camera went quiet.
  const new();
}

/// The phone could not write the received file.
final class TransferWriteFailed extends TransferFailure {
  /// Writing failed as [detail] says.
  const new(this.detail);

  /// The operating system's description of the failure.
  final String detail;
}

/// An error none of the other cases describe.
final class TransferOtherError extends TransferFailure {
  /// [detail] describes the error.
  const new(this.detail);

  /// The error as text, for diagnosis.
  final String detail;
}
