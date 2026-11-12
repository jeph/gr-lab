import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_camera/src/looks/look.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// The photos of one camera over one verified Wi-Fi link: listing, file
/// info, listing-change notices and transfers. A `CameraSession` gives a
/// new one each time its Wi-Fi comes up (`CameraSession.library`), so work
/// begun on a link that has since gone is told apart with `identical`.
final class CameraLibrary {
  new _(
    this._http, {
    required this.serial,
    required this._storages,
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
    GrChangesSocket? changes,
    Future<bool> Function()? checkWifi,
    TraceSink? trace,
  }) => CameraLibrary._(
    http,
    serial: serial,
    storages: () => storages,
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
  final List<String?> Function() _storages;
  final GrChangesSocket? Function() _changes;
  final Future<bool> Function()? _checkWifi;
  final void Function(String kind, Map<String, Object?> fields) _event;

  /// The paired camera's serial number.
  final String serial;

  /// Storages to list now: `in` and `sd1` on a two-storage camera, a single
  /// null (no `storage=` parameter) on a camera with one.
  List<String?> get storages => _storages();

  /// Emits when the listing may have changed: the camera's `/v1/changes`
  /// socket reports a storage change (a shot taken or deleted), or the
  /// socket opens again after a drop or a failed first open. The camera
  /// sends each change only to the sockets open at that moment and replays
  /// nothing (research/protocol/http-api.md §5), so what changed while it
  /// was closed shows only in a new listing. Done when the socket closes;
  /// empty when none is open.
  Stream<void> get listingChanges {
    final socket = _changes();
    if (socket == null) return const Stream.empty();
    final out = StreamController<void>();
    final subscriptions = <StreamSubscription<Object?>>[];
    void emit() {
      if (!out.isClosed) out.add(null);
    }

    out
      ..onListen = () {
        subscriptions
          ..add(
            socket.events.listen((e) {
              if (e is GrStorageChange) emit();
            }, onDone: out.close),
          )
          ..add(
            socket.statuses.listen((s) {
              if (s.state != GrSocketState.open) return;
              _event('library.changesReopened', {'socket': '$s'});
              emit();
            }),
          );
      }
      ..onCancel = () =>
          Future.wait([for (final s in subscriptions) s.cancel()]);
    return out.stream;
  }

  /// Lists every file on [storages], in the camera's order. A storage that
  /// answers with an error is left out while another one lists, and named
  /// in the result's `failed`: its files are unknown, not gone. The error
  /// is thrown when no storage lists. [reason] says why the listing is
  /// read (`connected`, `listingChange`, `user`), for the trace.
  Future<CameraListing> listFiles({String reason = 'request'}) async {
    final storages = this.storages;
    _event('library.list', {'reason': reason, 'storages': storages});
    final files = <CameraFile>[];
    final failed = <String?>{};
    GrApiException? failure;
    for (final storage in storages) {
      final found = <CameraFile>[];
      try {
        await for (final page in _http.photoPages(storage: storage)) {
          for (final p in page.paths) {
            found.add(CameraFile(storage, p));
          }
        }
        files.addAll(found);
      } on GrApiException catch (e) {
        // [listedStorages] leaves out storages the camera reports as not
        // available, so this one should list; another storage still does.
        _event('library.storageSkipped', {'storage': storage, 'error': '$e'});
        failed.add(storage);
        failure = e;
      }
    }
    if (failure != null && failed.length == storages.length) throw failure;
    _event('library.listed', {
      'reason': reason,
      'files': files.length,
      'failed': failed.toList(),
    });
    return (files: files, failed: failed);
  }

  /// The camera's `/info` for [f]. Once [abort] completes, the request
  /// stops at once and throws the value [abort] completed with.
  Future<FileInfo> fileInfo(CameraFile f, {Future<Object>? abort}) async =>
      fileInfoOf(
        await _http.photoInfo(f.path, storage: f.storage, abort: abort),
      );

  /// The Image Control [f] was shot with, from `/imgctrl` (http-api.md
  /// §4.3), as GR WORLD reads it to save a look from a photo. Throws
  /// [NoImageControl] when the camera's answer is not a blob GR Photo can
  /// read, and the HTTP client's errors otherwise.
  Future<Look> imageControl(CameraFile f) async {
    final bytes = await _http.imageControl(f.path, storage: f.storage);
    final look = Look.fromBytes(bytes);
    _event('library.imageControl', {
      'file': '$f',
      'hex': BleBytes.toHex(bytes),
      'decoded': look != null,
    });
    if (look == null) throw NoImageControl(bytes);
    return look;
  }

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
  /// Once [abort] completes, the transfer stops at once and throws the
  /// value [abort] completed with.
  Future<void> downloadFile(
    CameraFile f,
    File file, {
    void Function(int received, int? total)? onProgress,
    Future<Object>? abort,
  }) => _http.downloadToFile(
    f.path,
    file,
    storage: f.storage,
    onProgress: onProgress,
    abort: abort,
  );

  /// Copies [files] one at a time into [dir] and returns the copies, each
  /// under its camera name in a folder of [dir] named after its storage
  /// and camera folder, so same-named files from different storages or
  /// folders never share a copy. A copy already there (finished before a
  /// pause) is kept; only an interrupted one starts over, as the camera has
  /// no ranged downloads.
  ///
  /// [onProgress] gets the bytes of all files so far, the index of the
  /// file being copied, and that file's received bytes and length.
  /// [afterFile] runs after each file. Throwing from either stops the
  /// transfer with that error. Once [abort] completes, the transfer stops
  /// at once and throws the value [abort] completed with.
  Future<List<File>> downloadFiles(
    List<CameraFile> files,
    Directory dir, {
    required void Function(int bytes, int index, int received, int? total)
    onProgress,
    void Function()? afterFile,
    Future<Object>? abort,
  }) async {
    final local = <File>[];
    var before = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final folder = Directory('${dir.path}/${f.storage ?? 'x'}_${f.dir}');
      final out = File('${folder.path}/${f.name}');
      // A file finished before a pause stays; only the interrupted one
      // starts over.
      if (out.existsSync()) {
        _event('download.kept', {'file': '$f', 'path': out.path});
      } else {
        await folder.create(recursive: true);
        await downloadFile(
          f,
          out,
          onProgress: (received, total) =>
              onProgress(before + received, i, received, total),
          abort: abort,
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

/// What [CameraLibrary.listFiles] read: the files of every storage that
/// listed, in the camera's order, and the storages that answered with an
/// error instead (`failed`), whose files are unknown rather than gone.
typedef CameraListing = ({List<CameraFile> files, Set<String?> failed});

/// Builds a session's library; see [CameraLibrary]. [props] gives the
/// session's newest `/v1/props`, which decides the storages each listing
/// reads.
CameraLibrary newCameraLibrary(
  GrHttpClient http, {
  required String serial,
  required GrProps? Function() props,
  required GrChangesSocket? Function() changes,
  required Future<bool> Function() checkWifi,
  required void Function(String kind, Map<String, Object?> fields) event,
}) => CameraLibrary._(
  http,
  serial: serial,
  storages: () => listedStorages(props()),
  changes: changes,
  checkWifi: checkWifi,
  event: event,
);

/// Which storages to list, from `/v1/props`. GR WORLD adds `storage=` only
/// on cameras with two storages (http-api.md "Storage values"); a GR IV
/// lists only the SD card without it, so each storage is listed on its
/// own. A storage reported as not equipped or not available is left out:
/// GR IV webapid answers a listing of it with an error
/// (research/protocol/http-api.md "Storage values"), so its files are gone
/// for now rather than unknown.
List<String?> listedStorages(GrProps? props) {
  final storages = props?.storages ?? const <GrStorageInfo>[];
  if (storages.length < 2) return const [null];
  final names = [
    for (final s in storages)
      if (s.name case final name?
          when s.equipped != false && s.available != false)
        name,
  ];
  return names.isEmpty ? const [null] : names;
}

/// The camera's `/imgctrl` answer is not an Image Control blob.
final class NoImageControl implements Exception {
  /// The answer as received.
  const new(this.bytes);

  /// The bytes the camera sent.
  final Uint8List bytes;

  @override
  String toString() => 'NoImageControl(${BleBytes.toHex(bytes)})';
}

/// The error means the link to the camera broke (no answer, a reset
/// socket, a body cut short), rather than the camera refusing.
bool isConnectionError(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is TimeoutException ||
    error is GrMalformedResponseException;

/// Why a transfer from the camera failed. The app puts it into words; the
/// fields carry what the camera answered. The thrown error itself, with the
/// platform's description, is for the debug log.
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
    FileSystemException() => const TransferWriteFailed(),
    _ => const TransferOtherError(),
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
  /// Writing failed.
  const new();
}

/// An error none of the other cases describe.
final class TransferOtherError extends TransferFailure {
  /// Something else went wrong.
  const new();
}
