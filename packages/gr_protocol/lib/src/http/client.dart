import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gr_protocol/src/camera_address.dart';
import 'package:gr_protocol/src/http/changes.dart';
import 'package:gr_protocol/src/http/errors.dart';
import 'package:gr_protocol/src/http/json.dart';
import 'package:gr_protocol/src/http/liveview.dart';
import 'package:gr_protocol/src/http/mjpeg.dart';
import 'package:gr_protocol/src/http/models.dart';
import 'package:gr_protocol/src/http/request.dart';
import 'package:gr_protocol/src/http/sha256.dart';
import 'package:gr_protocol/src/trace.dart';

/// Per-route deadlines. Defaults follow connection-lifecycle.md §9 (connect
/// 3 s, read 10 s, downloads by idle timeout) and the apps' longer per-route
/// values where they exist (research/protocol/http-api.md §1,
/// connection-imagesync.md §2.1).
final class GrHttpTimeouts {
  /// Deadlines; each defaults to the value its field doc names.
  const new({
    this.connect = const Duration(seconds: 3),
    this.request = const Duration(seconds: 10),
    this.photoList = const Duration(seconds: 300),
    this.photoInfo = const Duration(seconds: 15),
    this.photoInfoList = const Duration(seconds: 120),
    this.imageControl = const Duration(seconds: 5),
    this.downloadIdle = const Duration(seconds: 30),
    this.firmwarePrepare = const Duration(seconds: 60),
    this.firmwareUpload = const Duration(seconds: 180),
    this.endScreen = const Duration(seconds: 60),
  });

  /// TCP connect (or reuse of a kept-alive connection).
  final Duration connect;

  /// Request sent through complete response body, for ordinary routes.
  final Duration request;

  /// Image Sync's `/v1/photos` read timeout (300 s).
  final Duration photoList;

  /// GR WORLD's per-photo info timeout (15 s).
  final Duration photoInfo;

  /// GR WORLD's native `/v1/photos/infos` timeout (120 s).
  final Duration photoInfoList;

  /// GR WORLD's `/imgctrl` timeout (5 s).
  final Duration imageControl;

  /// Longest silence while streaming an image.
  final Duration downloadIdle;

  /// GR WORLD's `/v1/configs/firmware/prepare` timeout (60 s).
  final Duration firmwarePrepare;

  /// GR WORLD's whole-file firmware `PUT` timeout (180 s).
  final Duration firmwareUpload;

  /// GR WORLD's end-screen `PUT` timeout (60 s).
  final Duration endScreen;
}

/// How `PUT /v1/photos/<dir>/<file>/transfer` is encoded.
enum GrTransferMarkStyle {
  /// GR WORLD (supports GR IV): `Content-Type: application/json`, body
  /// `storage=<s>` or empty; success is HTTP 200 (http-api.md §1 row 8).
  grWorld,

  /// Image Sync (GR III family): `text/plain`, body
  /// `status=transferred[&storage=<s>]`; success is `errCode == 200`
  /// (connection-imagesync.md §4).
  imageSync,
}

/// A response returned as text because its format is \[unknown\].
final class GrTextResponse {
  /// Response with status [httpStatus], [contentType] and body [text].
  const new(this.httpStatus, this.contentType, this.text, this.json);

  /// HTTP status code.
  final int httpStatus;

  /// `Content-Type` header, if the camera sent one.
  final String? contentType;

  /// Body decoded as UTF-8.
  final String text;

  /// The body parsed as camera JSON (check [CameraJson.issue]).
  final CameraJson json;
}

/// GR WORLD pages photo listings at 3000 files (http-api.md §2.1 step 6,
/// \[inferred\]).
const grWorldPhotoPageSize = 3000;

/// Client for the camera's Wi-Fi HTTP API (`http://<host>/v1/...`).
///
/// One keep-alive `HttpClient` serves every request, as recommended in
/// connection-lifecycle.md §9. Pass [httpClient] to supply one whose
/// `connectionFactory` binds sockets to the camera network; it is then not
/// closed by [close]. `socketConnector` does the same for live view, which
/// uses a raw socket.
///
/// Every exchange emits [TraceEvent]s on [TraceChannel.http] when a sink is
/// given: method, URL and all headers of each request and response, JSON
/// and text bodies in full, and for binary bodies (images, DNG, movies)
/// only their type, length and headers.
final class GrHttpClient {
  /// Client for the camera at [host]; nothing connects until a request.
  new(
    this.host, {
    this.port = grCameraHttpPort,
    HttpClient? httpClient,
    this._trace,
    this.timeouts = const GrHttpTimeouts(),
    this._socketConnector = defaultSocketConnector,
  }) : _http =
           httpClient ?? (HttpClient()..connectionTimeout = timeouts.connect),
       _ownsHttp = httpClient == null;

  /// Camera address, [grCameraHost] on the camera's own access point.
  final String host;

  /// HTTP port of the camera's web API, [grCameraHttpPort] on a camera.
  final int port;

  /// Per-route deadlines.
  final GrHttpTimeouts timeouts;
  final HttpClient _http;
  final bool _ownsHttp;
  final TraceSink? _trace;
  final GrSocketConnector _socketConnector;

  /// The underlying client (for WebSockets sharing its connection settings).
  HttpClient get httpClient => _http;

  // ---------------------------------------------------------------- identity

  /// `GET /v1/props` (http-api.md §1 row 1, remote-shooting.md §4.1).
  /// Image Sync uses 7 s connect / 10 s read, its liveness checker 1 s / 10 s.
  Future<GrProps> props({Duration? connectTimeout, Duration? timeout}) async =>
      GrProps(
        await _json(
          'GET',
          _uri(['props']),
          connectTimeout: connectTimeout,
          timeout: timeout,
        ),
      );

  /// `GET /v1/ping`: registered by GR III/IV firmware; it reads the camera
  /// datetime (firmware-protocol-inventory.md "Additional-route
  /// verification"). Not used by either of Ricoh's apps on III/IV; GR Photo's
  /// liveness probe. Answered by a GR IV HDF (fw 1.20, 2026-11-11,
  /// hardware-validation.md §4).
  Future<GrPing> ping({Duration? connectTimeout, Duration? timeout}) async =>
      GrPing(
        await _json(
          'GET',
          _uri(['ping']),
          connectTimeout: connectTimeout,
          timeout: timeout,
        ),
      );

  /// `GET /v1/status/device` (http-api.md §1 row 2). GR WORLD uses it on GR
  /// II; it may not exist on GR III/IV (no route literal in their webapid,
  /// connection-lifecycle.md §9).
  Future<GrDeviceStatus> deviceStatus() async =>
      GrDeviceStatus(await _json('GET', _uri(['status', 'device'])));

  // ------------------------------------------------------------------ photos

  /// One `GET /v1/photos[?storage=][&limit=][&after=dir/file]` page
  /// (http-api.md §2.1; `limit` is Image Sync's, connection-imagesync.md §4).
  Future<GrPhotoList> photos({
    String? storage,
    int? limit,
    GrPhotoPath? after,
  }) async {
    if (limit != null && limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be ≥ 1');
    }
    return GrPhotoList(
      await _json(
        'GET',
        _uri(
          ['photos'],
          {
            if (storage != null) 'storage': GrStorageId.validate(storage),
            if (limit != null) 'limit': '$limit',
            if (after != null) 'after': '$after',
          },
        ),
        timeout: timeouts.photoList,
      ),
    );
  }

  /// Every page, following the `after=<last dir/file>` cursor. With [limit]
  /// the Image Sync rule applies (stop when a page holds fewer than [limit]
  /// files); without it GR WORLD's (stop below [grWorldPhotoPageSize]). Also
  /// stops when the cursor does not advance.
  Stream<GrPhotoList> photoPages({String? storage, int? limit}) async* {
    final pageSize = limit ?? grWorldPhotoPageSize;
    GrPhotoPath? after;
    while (true) {
      final page = await photos(storage: storage, limit: limit, after: after);
      yield page;
      final last = page.last;
      if (page.fileCount < pageSize || last == null || last == after) return;
      after = last;
    }
  }

  /// `GET /v1/photos/<dir>/<file>/info[?storage=]` (http-api.md §2.2).
  /// Once [abort] completes, the request stops and its connection is closed
  /// at once, and [photoInfo] throws the value [abort] completed with.
  Future<GrPhotoInfo> photoInfo(
    GrPhotoPath path, {
    String? storage,
    Future<Object>? abort,
  }) async => GrPhotoInfo(
    await _json(
      'GET',
      _uri(['photos', path.dir, path.file, 'info'], _storage(storage)),
      timeout: timeouts.photoInfo,
      abort: abort,
    ),
  );

  /// `GET /v1/photos/latest/info`: Image Sync's fallback when no WebSocket
  /// `filepath` was seen. GR III/IV webapid has no `/latest` route; a GR IV
  /// HDF (fw 1.20) answers errCode 400 under HTTP 200, raised here as
  /// [GrApiException] (hardware-validation.md §4). On those models use the
  /// last entry of [photoPages] with [photoInfo].
  Future<GrPhotoInfo> latestPhotoInfo() async => GrPhotoInfo(
    await _json(
      'GET',
      _uri(['photos', 'latest', 'info']),
      timeout: timeouts.photoInfo,
    ),
  );

  /// `GET /v1/photos/infos?storage=<s>[&after=]`: implemented natively in GR
  /// WORLD but never invoked from Dart; the response shape is \[unknown\], so
  /// the envelope is returned raw (http-api.md §1 row 6, §3).
  Future<GrEnvelope> photoInfoList({
    required String storage,
    GrPhotoPath? after,
  }) async => GrEnvelope(
    await _json(
      'GET',
      _uri(
        ['photos', 'infos'],
        {
          'storage': GrStorageId.validate(storage),
          if (after != null) 'after': '$after',
        },
      ),
      timeout: timeouts.photoInfoList,
    ),
  );

  /// URL of an image: `/v1/photos/<dir>/<file>?size=<s>[&storage=<s>]`, the
  /// order GR WORLD's download builder uses (http-api.md §2.4). `size: null`
  /// omits the parameter, Image Sync's full-size form.
  Uri photoUri(GrPhotoPath path, {GrImageSize? size, String? storage}) => _uri(
    ['photos', path.dir, path.file],
    {if (size != null) 'size': size.name, ..._storage(storage)},
  );

  /// Streams an image into [sink] (not closed here).
  ///
  /// Like both apps: one GET, no `Range`/resume; a body starting with `{` is
  /// a JSON error even under HTTP 200 (http-api.md §2.4 step 4,
  /// connection-imagesync.md §4) and raises [GrApiException]. A body shorter
  /// than its `Content-Length` raises [GrMalformedResponseException]. A
  /// silence longer than [GrHttpTimeouts.downloadIdle], in the image or in
  /// an error answer, raises [TimeoutException].
  ///
  /// Once [abort] completes, the transfer stops and its connection is
  /// closed at once, and [download] throws the value [abort] completed with.
  Future<GrDownloadResult> download(
    GrPhotoPath path,
    StreamSink<List<int>> sink, {
    GrImageSize? size = GrImageSize.full,
    String? storage,
    void Function(int received, int? total)? onProgress,
    Future<Object>? abort,
  }) async {
    final uri = photoUri(path, size: size, storage: storage);
    final route = 'GET ${uri.path}';
    final watch = Stopwatch()..start();
    final request = await _open('GET', uri, timeouts.connect);
    request.done.ignore();
    // Until the response arrives; after that [_consume] stops the body.
    unawaited(abort?.then(request.abort));
    _traceRequest(request, null, null);
    try {
      final response = await request.close().timeout(timeouts.request);
      final total = response.contentLength >= 0 ? response.contentLength : null;
      if (response.statusCode != 200) {
        final body = await _readBody(
          response,
          route,
          idle: timeouts.downloadIdle,
          stop: abort,
        );
        _traceResponse(uri, response, body, watch.elapsed);
        _throwForError(route, response.statusCode, body);
        throw GrHttpStatusException(
          route: route,
          httpStatus: response.statusCode,
        );
      }
      var received = 0;
      BytesBuilder? jsonBody;
      var first = true;
      await _consume(
        response,
        route,
        (chunk) {
          if (chunk.isEmpty) return;
          if (first) {
            first = false;
            if (chunk[0] == 0x7B) jsonBody = BytesBuilder();
          }
          if (jsonBody case final json?) {
            // Kept whole for the error and the trace, within the bound every
            // other response has.
            if (json.length + chunk.length > _maxBodyBytes) {
              throw GrMalformedResponseException(
                route: route,
                httpStatus: response.statusCode,
                issue: 'response body exceeds $_maxBodyBytes bytes',
              );
            }
            json.add(chunk);
            return;
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        },
        idle: timeouts.downloadIdle,
        stop: abort,
      );
      if (jsonBody case final json?) {
        final body = json.takeBytes();
        _traceResponse(uri, response, body, watch.elapsed);
        _throwForError(route, response.statusCode, body);
        throw GrMalformedResponseException(
          route: route,
          httpStatus: response.statusCode,
          issue: 'JSON body instead of image data',
          bodyText: utf8.decode(body, allowMalformed: true),
        );
      }
      _trace?.call(
        TraceEvent(
          channel: TraceChannel.http,
          direction: TraceDirection.inbound,
          kind: 'response',
          fields: {
            'method': 'GET',
            'url': uri.toString(),
            'status': response.statusCode,
            'headers': _headerMap(response.headers),
            'contentType': response.headers.contentType?.toString(),
            'contentLength': total,
            'bodyLength': received,
            'elapsedMs': watch.elapsedMilliseconds,
          },
        ),
      );
      if (total != null && received != total) {
        throw GrMalformedResponseException(
          route: route,
          httpStatus: response.statusCode,
          issue: 'body ended after $received of $total bytes',
        );
      }
      return GrDownloadResult(
        path: path,
        size: size,
        bytes: received,
        contentLength: total,
        contentType: response.headers.contentType?.toString(),
        elapsed: watch.elapsed,
      );
    } catch (e) {
      request.abort(e);
      _traceError('GET', uri, e);
      rethrow;
    }
  }

  /// [download] into [file] via `<file>.part`, renamed on success and deleted
  /// on failure.
  Future<GrDownloadResult> downloadToFile(
    GrPhotoPath path,
    File file, {
    GrImageSize? size = GrImageSize.full,
    String? storage,
    void Function(int received, int? total)? onProgress,
    Future<Object>? abort,
  }) async {
    final part = File('${file.path}.part');
    final sink = part.openWrite();
    try {
      final result = await download(
        path,
        sink,
        size: size,
        storage: storage,
        onProgress: onProgress,
        abort: abort,
      );
      await sink.flush();
      await sink.close();
      await part.rename(file.path);
      return result;
    } catch (_) {
      await sink.close().catchError((Object _) {});
      if (part.existsSync()) await part.delete();
      rethrow;
    }
  }

  /// `GET /v1/photos/<dir>/<file>/imgctrl[?storage=]`: the raw Image Control
  /// BLOB (http-api.md §4.3). Its layout is shared with the BLE Image Control
  /// characteristics (ble.md § Image Control blob).
  Future<Uint8List> imageControl(GrPhotoPath path, {String? storage}) async {
    final uri = _uri([
      'photos',
      path.dir,
      path.file,
      'imgctrl',
    ], _storage(storage));
    final reply = await _send('GET', uri, timeout: timeouts.imageControl);
    _throwForError(reply.route, reply.status, reply.body);
    if (reply.status != 200) {
      throw GrHttpStatusException(
        route: reply.route,
        httpStatus: reply.status,
        bodyText: utf8.decode(reply.body, allowMalformed: true),
      );
    }
    // A valid BLOB starts with version 1, 2 or 4, never `{`.
    if (reply.body.isNotEmpty && reply.body[0] == 0x7B) {
      throw GrMalformedResponseException(
        route: reply.route,
        httpStatus: reply.status,
        issue: 'JSON body instead of an Image Control BLOB',
        bodyText: utf8.decode(reply.body, allowMalformed: true),
      );
    }
    return reply.body;
  }

  // --------------------------------------------------------------- transfers

  /// `GET /v1/transfers?status=untransferred[&limit=][&storage=][&after=]`
  /// (http-api.md §2.5; `limit`/`after=<index>` from Image Sync,
  /// connection-imagesync.md §4).
  Future<GrTransferList> transfers({
    String? storage,
    int? limit,
    int? after,
  }) async => GrTransferList(
    await _json(
      'GET',
      _uri(
        ['transfers'],
        {
          'status': 'untransferred',
          if (limit != null) 'limit': '$limit',
          if (storage != null) 'storage': GrStorageId.validate(storage),
          if (after != null) 'after': '$after',
        },
      ),
    ),
  );

  /// `PUT /v1/photos/<dir>/<file>/transfer`: marks a reserved transfer done.
  /// Returns the response envelope when the camera sent one.
  Future<GrEnvelope?> markTransferred(
    GrPhotoPath path, {
    String? storage,
    GrTransferMarkStyle style = GrTransferMarkStyle.grWorld,
  }) async {
    final s = storage == null ? null : GrStorageId.validate(storage);
    final uri = _uri(['photos', path.dir, path.file, 'transfer']);
    switch (style) {
      case GrTransferMarkStyle.grWorld:
        return await _statusOrEnvelope(
          'PUT',
          uri,
          body: encodeKeyValueBodyBytes({'storage': ?s}),
          contentType: GrContentType.jsonLabelled,
        );
      case GrTransferMarkStyle.imageSync:
        return GrEnvelope(
          await _json(
            'PUT',
            uri,
            body: encodeKeyValueBodyBytes({
              'status': 'transferred',
              'storage': ?s,
            }),
            contentType: GrContentType.textPlain,
          ),
        );
    }
  }

  // ------------------------------------------------------------------ params

  /// `PUT /v1/params/camera` with `key=value&…` (remote-shooting.md §4.2).
  /// The response is props-shaped. Only values in the camera's `<key>List`
  /// are valid; see [GrProps.offers]. An empty map would be the green
  /// button, so it is rejected; use [pressGreenButton].
  Future<GrProps> setCameraParams(Map<String, String> params) async {
    if (params.isEmpty) {
      throw ArgumentError(
        'empty params is the green button; use pressGreenButton',
      );
    }
    return GrProps(await _put(['params', 'camera'], params));
  }

  /// Empty-body `PUT /v1/params/camera`: Image Sync's "green button"
  /// (remote-shooting.md §2.1).
  Future<GrProps> pressGreenButton() async => GrProps(
    await _json(
      'PUT',
      _uri(['params', 'camera']),
      body: const [],
      contentType: GrContentType.textPlain,
    ),
  );

  /// `PUT /v1/params/lens`, e.g. `focusSetting=<v>` (remote-shooting.md
  /// §3.3). Response shape \[unknown\]; parsed as props-shaped.
  Future<GrProps> setLensParams(Map<String, String> params) async {
    if (params.isEmpty) throw ArgumentError('no lens params');
    return GrProps(await _put(['params', 'lens'], params));
  }

  /// `PUT /v1/params/device` as Image Sync sends it (`text/plain`), e.g.
  /// `stillFormat=rawdng` or `datetime=…` (remote-shooting.md §4.2–4.3).
  /// Response shape \[unknown\]; parsed as props-shaped. Credential, channel,
  /// BLE-enable and name keys change persistent camera state.
  Future<GrProps> setDeviceParams(Map<String, String> params) async {
    if (params.isEmpty) throw ArgumentError('no device params');
    return GrProps(await _put(['params', 'device'], params));
  }

  /// GR II Wi-Fi settings exactly as GR WORLD writes them: `PUT
  /// /v1/params/device`, `Content-Type: application/json`, body
  /// `channel=<c>&ssid=<ssid>&key=<password>` unescaped; success is HTTP 200
  /// (http-api.md §1 row 12, §4.2). GR WORLD always sends `channel=0`.
  Future<GrEnvelope?> setGr2WifiSettings({
    required String ssid,
    required String key,
    int channel = 0,
  }) => _statusOrEnvelope(
    'PUT',
    _uri(['params', 'device']),
    body: encodeKeyValueBodyBytes({
      'channel': '$channel',
      'ssid': ssid,
      'key': key,
    }),
    contentType: GrContentType.jsonLabelled,
  );

  // ---------------------------------------------------------------- shooting

  /// `POST /v1/camera/shoot` (remote-shooting.md §2.1): body `""` (Image Sync
  /// "no AF" while live view runs), `af=on`, or `af=on&pos=X,Y`. On GR III/IV
  /// the same POST also stops movie/bulb/time and continuous/interval capture.
  Future<GrShootResult> shoot({GrShootAf? af, GrFocusPoint? pos}) async =>
      GrShootResult(
        await _json(
          'POST',
          _uri(['camera', 'shoot']),
          body: utf8.encode(shootBody(af: af, pos: pos)),
          contentType: GrContentType.textPlain,
        ),
      );

  /// `POST /v1/camera/shoot/start`: GR II / SDK-default movie start. Absent
  /// from GR III/IV webapid (remote-shooting.md §6).
  Future<GrShootResult> shootStart({GrShootAf? af}) async => GrShootResult(
    await _json(
      'POST',
      _uri(['camera', 'shoot', 'start']),
      body: utf8.encode(shootBody(af: af)),
      contentType: GrContentType.textPlain,
    ),
  );

  /// `POST /v1/camera/shoot/finish`: GR II / SDK-default stop. Absent from
  /// GR III/IV webapid.
  Future<GrShootResult> shootFinish() async => GrShootResult(
    await _json(
      'POST',
      _uri(['camera', 'shoot', 'finish']),
      body: const [],
      contentType: GrContentType.textPlain,
    ),
  );

  /// `POST /v1/camera/shoot/compose`: ends interval-composite capture
  /// (remote-shooting.md §2.1; firmware `Compose`).
  Future<GrShootResult> composeShoot() async => GrShootResult(
    await _json(
      'POST',
      _uri(['camera', 'shoot', 'compose']),
      body: const [],
      contentType: GrContentType.textPlain,
    ),
  );

  /// `POST /v1/camera/shoot/cancel`: cancels a self-timer countdown
  /// (firmware `CancelTimer`, remote-shooting.md §2.1).
  Future<GrShootResult> cancelShootTimer() async => GrShootResult(
    await _json(
      'POST',
      _uri(['camera', 'shoot', 'cancel']),
      body: const [],
      contentType: GrContentType.textPlain,
    ),
  );

  /// `POST /v1/lens/focus` with `pos=X,Y` or `""` (remote-shooting.md §3.1).
  /// A non-empty [GrFocusResult.captureId] means the result follows as a
  /// WebSocket `lens` event (Image Sync waits up to 40 s).
  Future<GrFocusResult> focus({GrFocusPoint? pos}) async => GrFocusResult(
    await _json(
      'POST',
      _uri(['lens', 'focus']),
      body: encodeKeyValueBodyBytes({'pos': ?pos?.wire}),
      contentType: GrContentType.textPlain,
    ),
  );

  /// `POST /v1/lens/focus/lock` with `pos=X,Y`: GR II only; absent from GR
  /// III/IV firmware (remote-shooting.md §3.1).
  Future<GrFocusResult> focusLockGr2(GrFocusPoint pos) async => GrFocusResult(
    await _json(
      'POST',
      _uri(['lens', 'focus', 'lock']),
      body: encodeKeyValueBodyBytes({'pos': pos.wire}),
      contentType: GrContentType.textPlain,
    ),
  );

  /// Opens `GET /v1/liveview` (remote-shooting.md §1). See
  /// [LiveViewStream.open].
  Future<LiveViewStream> openLiveView({
    int? maxFps,
    String? reso,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration? idleTimeout = const Duration(seconds: 10),
    int maxFrameBytes = MjpegSplitter.defaultMaxFrameBytes,
  }) => LiveViewStream.open(
    host,
    port: port,
    maxFps: maxFps,
    reso: reso,
    connectTimeout: connectTimeout,
    idleTimeout: idleTimeout,
    maxFrameBytes: maxFrameBytes,
    trace: _trace,
    connector: _socketConnector,
  );

  /// A `ws://<host>/v1/changes` client sharing this client's `HttpClient`.
  GrChangesSocket changesSocket({
    Duration connectTimeout = const Duration(seconds: 7),
    GrReconnectPolicy reconnect = const GrBackoffReconnect(),
  }) => GrChangesSocket(
    host,
    port: port,
    httpClient: _http,
    connectTimeout: connectTimeout,
    reconnect: reconnect,
    trace: _trace,
  );

  // ------------------------------------------------------------ device power

  /// `POST /v1/device/finish`: powers the camera off. Sent as GR WORLD sends
  /// it: empty body, no Content-Type, success is HTTP 200
  /// (http-api.md §1 row 3, §4.5). An explicit JSON errCode ≠ 200 still
  /// raises [GrApiException].
  Future<GrEnvelope?> powerOff() =>
      _statusOrEnvelope('POST', _uri(['device', 'finish']), body: const []);

  /// `POST /v1/device/wlan/finish`: turns the camera's WLAN off
  /// (`ChangeWlanMode(0)`), ending this connection
  /// (remote-shooting.md §2.1, §6).
  Future<GrEnvelope?> finishWlan() => _statusOrEnvelope(
    'POST',
    _uri(['device', 'wlan', 'finish']),
    body: const [],
    contentType: GrContentType.textPlain,
  );

  // ------------------------------------------------------------ diagnostics

  /// `GET /v1/debug/revisions`: firmware runs `cat /etc/revisions/*` and
  /// returns its output or `failed to get revisions.`
  /// (firmware-protocol-inventory.md). Diagnostic route; response framing
  /// \[unknown\], so the text is returned.
  Future<GrTextResponse> debugRevisions() async {
    final reply = await _send('GET', _uri(['debug', 'revisions']));
    _throwForError(reply.route, reply.status, reply.body);
    if (reply.status != 200) {
      throw GrHttpStatusException(
        route: reply.route,
        httpStatus: reply.status,
        bodyText: utf8.decode(reply.body, allowMalformed: true),
      );
    }
    final json = decodeCameraJsonBytes(reply.body);
    return GrTextResponse(
      reply.status,
      reply.contentType,
      utf8.decode(reply.body, allowMalformed: true),
      json,
    );
  }

  /// `GET /v1/logs/camera?type=monthly_capture&date=YYYY-MM`
  /// (http-api.md §6).
  Future<GrCameraLog> cameraLog({required int year, required int month}) async {
    if (year < 1000 || year > 9999) {
      throw RangeError.range(year, 1000, 9999, 'year');
    }
    if (month < 1 || month > 12) throw RangeError.range(month, 1, 12, 'month');
    return GrCameraLog(
      await _json(
        'GET',
        _uri(
          ['logs', 'camera'],
          {
            'type': 'monthly_capture',
            'date': '$year-${month.toString().padLeft(2, '0')}',
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- firmware

  /// `POST /v1/configs/firmware/prepare`, form body `filesize=<bytes>`
  /// (http-api.md §7 step 2). Rejections carry
  /// [GrApiException.firmwareRejection].
  Future<GrEnvelope> prepareFirmware(int fileSize) async {
    if (fileSize <= 0) throw ArgumentError.value(fileSize, 'fileSize', '> 0');
    return GrEnvelope(
      await _json(
        'POST',
        _uri(['configs', 'firmware', 'prepare']),
        body: ascii.encode('filesize=$fileSize'),
        contentType: GrContentType.formUrlEncoded,
        timeout: timeouts.firmwarePrepare,
      ),
    );
  }

  /// `PUT /v1/configs/firmware?storage=in&reboot=true` with the whole file as
  /// one `application/octet-stream` body (http-api.md §7 step 3). The camera
  /// reboots by itself when [reboot] is true.
  Future<GrEnvelope> uploadFirmware(
    File firmware, {
    String storage = GrStorageId.internal,
    bool reboot = true,
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await firmware.length();
    return GrEnvelope(
      await _json(
        'PUT',
        _uri(
          ['configs', 'firmware'],
          {'storage': GrStorageId.validate(storage), 'reboot': '$reboot'},
        ),
        bodyFile: firmware,
        bodyFileLength: length,
        onSendProgress: onProgress,
        contentType: GrContentType.octetStream,
        timeout: timeouts.firmwareUpload,
      ),
    );
  }

  /// `POST /v1/configs/firmware/cancel`, no headers, no body
  /// (http-api.md §7 step 5).
  Future<GrEnvelope?> cancelFirmware() => _statusOrEnvelope(
    'POST',
    _uri(['configs', 'firmware', 'cancel']),
    body: const [],
  );

  /// `PUT /v1/device/image/endscreen?index=<n>[&sha256=<hex>]`,
  /// `Content-Type: image/jpeg` (http-api.md §4.4). With [jpeg]: GR WORLD's
  /// variant A (body plus lowercase SHA-256 when [includeSha256]). Without:
  /// variant B (no body, no hash), \[inferred\] to reset slot [index].
  Future<GrEnvelope> uploadEndScreen(
    int index, {
    Uint8List? jpeg,
    bool includeSha256 = true,
  }) async {
    if (index < 0) throw RangeError.value(index, 'index', 'must be ≥ 0');
    return GrEnvelope(
      await _json(
        'PUT',
        _uri(
          ['device', 'image', 'endscreen'],
          {
            'index': '$index',
            if (jpeg != null && includeSha256) 'sha256': hexLower(sha256(jpeg)),
          },
        ),
        body: jpeg ?? const [],
        contentType: GrContentType.imageJpeg,
        timeout: timeouts.endScreen,
      ),
    );
  }

  /// Closes the owned `HttpClient`; an injected one is left open.
  void close({bool force = false}) {
    if (_ownsHttp) _http.close(force: force);
  }

  // ---------------------------------------------------------------- plumbing

  Uri _uri(List<String> segments, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: host,
    port: port,
    pathSegments: ['v1', ...segments],
    query: query == null ? null : encodeQuery(query),
  );

  Map<String, String> _storage(String? storage) => {
    if (storage != null) 'storage': GrStorageId.validate(storage),
  };

  Future<Map<String, Object?>> _put(
    List<String> segments,
    Map<String, String> params,
  ) => _json(
    'PUT',
    _uri(segments),
    body: encodeKeyValueBodyBytes(params),
    contentType: GrContentType.textPlain,
  );

  /// Sends a request whose success is decided by the JSON `errCode`.
  Future<Map<String, Object?>> _json(
    String method,
    Uri uri, {
    List<int>? body,
    File? bodyFile,
    int? bodyFileLength,
    void Function(int sent, int total)? onSendProgress,
    GrContentType? contentType,
    Duration? connectTimeout,
    Duration? timeout,
    Future<Object>? abort,
  }) async {
    final reply = await _send(
      method,
      uri,
      body: body,
      bodyFile: bodyFile,
      bodyFileLength: bodyFileLength,
      onSendProgress: onSendProgress,
      contentType: contentType,
      connectTimeout: connectTimeout,
      timeout: timeout,
      abort: abort,
    );
    _throwForError(reply.route, reply.status, reply.body);
    final json = decodeCameraJsonBytes(reply.body);
    final map = json.object;
    if (reply.status != 200 &&
        (map == null || GrEnvelope(map).errCode == null)) {
      throw GrHttpStatusException(
        route: reply.route,
        httpStatus: reply.status,
        bodyText: json.text,
      );
    }
    if (map == null) {
      throw GrMalformedResponseException(
        route: reply.route,
        httpStatus: reply.status,
        issue: json.issue ?? 'not a JSON object',
        bodyText: json.text,
      );
    }
    return map;
  }

  /// Sends a request whose success is HTTP 200 (GR WORLD's native calls),
  /// still honouring an explicit JSON errCode. Returns the envelope if the
  /// body was a JSON object.
  Future<GrEnvelope?> _statusOrEnvelope(
    String method,
    Uri uri, {
    List<int>? body,
    GrContentType? contentType,
  }) async {
    final reply = await _send(
      method,
      uri,
      body: body,
      contentType: contentType,
    );
    _throwForError(reply.route, reply.status, reply.body);
    final map = decodeCameraJsonBytes(reply.body).object;
    if (reply.status != 200) {
      throw GrHttpStatusException(
        route: reply.route,
        httpStatus: reply.status,
        bodyText: utf8.decode(reply.body, allowMalformed: true),
      );
    }
    return map == null ? null : GrEnvelope(map);
  }

  /// Throws [GrApiException] when [body] is a JSON envelope with
  /// `errCode != 200`.
  void _throwForError(String route, int status, List<int> body) {
    if (body.isEmpty || body.first != 0x7B) return;
    final map = decodeCameraJsonBytes(body).object;
    if (map == null) return;
    final env = GrEnvelope(map);
    final code = env.errCode;
    if (code != null && code != 200) {
      throw GrApiException(
        errCode: code,
        errMsg: env.errMsg,
        reason: env.reason,
        route: route,
        httpStatus: status,
        body: map,
      );
    }
  }

  /// Opens a request with a per-call connect deadline. `HttpClient` cannot
  /// cancel a pending connect, so a late connection is aborted when it
  /// arrives.
  Future<HttpClientRequest> _open(
    String method,
    Uri uri,
    Duration connectTimeout,
  ) async {
    final pending = _http.openUrl(method, uri);
    try {
      return await pending.timeout(connectTimeout);
    } on TimeoutException {
      unawaited(
        pending.then<void>((r) {
          r.done.ignore();
          r.abort();
        }, onError: (Object _) {}),
      );
      final e = TimeoutException(
        '$method ${uri.path}: no connection within $connectTimeout',
        connectTimeout,
      );
      _traceError(method, uri, e);
      throw e;
    } catch (e) {
      _traceError(method, uri, e);
      rethrow;
    }
  }

  Future<_Reply> _send(
    String method,
    Uri uri, {
    List<int>? body,
    File? bodyFile,
    int? bodyFileLength,
    void Function(int sent, int total)? onSendProgress,
    GrContentType? contentType,
    Duration? connectTimeout,
    Duration? timeout,
    Future<Object>? abort,
  }) async {
    final route = '$method ${uri.path}';
    final watch = Stopwatch()..start();
    final request = await _open(
      method,
      uri,
      connectTimeout ?? timeouts.connect,
    );
    request.done.ignore();
    final deadline = timeout ?? timeouts.request;
    // Completed when the deadline passes or [abort] completes, to close a
    // body still arriving.
    final stop = Completer<Object>();
    Object? aborted;
    unawaited(
      abort?.then((reason) {
        aborted = reason;
        // Abort ends the request only until the response has arrived; the
        // body is closed through [stop].
        request.abort(reason);
        if (!stop.isCompleted) stop.complete(reason);
      }),
    );
    try {
      final reply = await _exchange(
        request,
        route,
        body: body,
        bodyFile: bodyFile,
        bodyFileLength: bodyFileLength,
        onSendProgress: onSendProgress,
        contentType: contentType,
        stop: stop.future,
      ).timeout(deadline);
      _trace?.call(
        TraceEvent(
          channel: TraceChannel.http,
          direction: TraceDirection.inbound,
          kind: 'response',
          fields: {
            'method': method,
            'url': uri.toString(),
            'status': reply.status,
            'headers': reply.headers,
            'contentType': reply.contentType,
            'bodyLength': reply.body.length,
            'elapsedMs': watch.elapsedMilliseconds,
            ..._bodyField(reply.contentType, reply.body),
          },
        ),
      );
      return reply;
    } on Object catch (e, stack) {
      // An abort can surface as the socket error it caused; the caller gets
      // what [abort] completed with.
      if (aborted case final reason?) {
        _traceError(method, uri, reason);
        Error.throwWithStackTrace(reason, stack);
      }
      if (e is! TimeoutException) {
        request.abort(e);
        _traceError(method, uri, e);
        rethrow;
      }
      final timeout = TimeoutException(
        '$route: no complete response within $deadline',
        deadline,
      );
      request.abort(timeout);
      if (!stop.isCompleted) stop.complete(timeout);
      _traceError(method, uri, timeout);
      throw timeout;
    }
  }

  Future<_Reply> _exchange(
    HttpClientRequest request,
    String route, {
    required Future<Object> stop,
    List<int>? body,
    File? bodyFile,
    int? bodyFileLength,
    void Function(int sent, int total)? onSendProgress,
    GrContentType? contentType,
  }) async {
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType.header);
    }
    if (bodyFile != null) {
      final total = bodyFileLength ?? await bodyFile.length();
      request.contentLength = total;
      _traceRequest(request, null, total);
      var sent = 0;
      await request.addStream(
        bodyFile.openRead().map((chunk) {
          sent += chunk.length;
          onSendProgress?.call(sent, total);
          return chunk;
        }),
      );
    } else if (body != null) {
      request.contentLength = body.length;
      _traceRequest(request, body, null);
      if (body.isNotEmpty) request.add(body);
    } else {
      _traceRequest(request, null, null);
    }
    final response = await request.close();
    final bytes = await _readBody(response, route, stop: stop);
    return _Reply(
      route,
      response.statusCode,
      response.headers.contentType?.toString(),
      _headerMap(response.headers),
      bytes,
    );
  }

  /// Largest response body read into memory (images stream instead).
  static const int _maxBodyBytes = 32 * 1024 * 1024;

  /// The whole body of [response], read as [_consume] reads it.
  Future<Uint8List> _readBody(
    HttpClientResponse response,
    String route, {
    Duration? idle,
    Future<Object>? stop,
  }) async {
    final builder = BytesBuilder(copy: false);
    await _consume(
      response,
      route,
      (chunk) {
        if (builder.length + chunk.length > _maxBodyBytes) {
          throw GrMalformedResponseException(
            route: route,
            httpStatus: response.statusCode,
            issue: 'response body exceeds $_maxBodyBytes bytes',
          );
        }
        builder.add(chunk);
      },
      idle: idle,
      stop: stop,
    );
    return builder.takeBytes();
  }

  /// Hands [response]'s body to [onChunk] through a subscription of its
  /// own, so that a deadline can end it: once the response has arrived,
  /// `HttpClientRequest.abort` has no effect, and cancelling the body's
  /// subscription is what closes the connection. Fails with what [onChunk]
  /// throws, with [TimeoutException] after [idle] without data, or with the
  /// value [stop] completes with; each of those closes the connection.
  static Future<void> _consume(
    HttpClientResponse response,
    String route,
    void Function(List<int> chunk) onChunk, {
    Duration? idle,
    Future<Object>? stop,
  }) {
    final done = Completer<void>();
    late final StreamSubscription<List<int>> body;
    Timer? silence;
    void fail(Object error, StackTrace stack) {
      if (done.isCompleted) return;
      silence?.cancel();
      unawaited(body.cancel());
      done.completeError(error, stack);
    }

    void waitForData() {
      if (idle == null) return;
      silence?.cancel();
      silence = Timer(
        idle,
        () => fail(
          TimeoutException('$route: no data within $idle', idle),
          StackTrace.current,
        ),
      );
    }

    body = response.listen(
      (chunk) {
        if (done.isCompleted) return;
        try {
          onChunk(chunk);
        } on Object catch (e, st) {
          fail(e, st);
          return;
        }
        waitForData();
      },
      onError: fail,
      onDone: () {
        if (done.isCompleted) return;
        silence?.cancel();
        done.complete();
      },
    );
    waitForData();
    unawaited(stop?.then((reason) => fail(reason, StackTrace.current)));
    return done.future;
  }

  /// Traces [request] once its headers are final, with [body] in full when
  /// it is text; a file upload is traced by its length ([fileLength]).
  void _traceRequest(
    HttpClientRequest request,
    List<int>? body,
    int? fileLength,
  ) {
    final trace = _trace;
    if (trace == null) return;
    final contentType = request.headers.contentType?.toString();
    trace(
      TraceEvent(
        channel: TraceChannel.http,
        direction: TraceDirection.outbound,
        kind: 'request',
        fields: {
          'method': request.method,
          'url': request.uri.toString(),
          'headers': _headerMap(request.headers),
          'contentType': contentType,
          'bodyLength': body?.length ?? fileLength,
          if (body != null) ..._bodyField(contentType, body),
        },
      ),
    );
  }

  /// Every header, repeated values joined as HTTP joins them.
  static Map<String, String> _headerMap(HttpHeaders headers) {
    final map = <String, String>{};
    headers.forEach((name, values) => map[name] = values.join(', '));
    return map;
  }

  /// A JSON, form or text body as `body` text, in full. Binary bodies
  /// (images, DNG, movies) are left out: their type and length say enough.
  static Map<String, Object?> _bodyField(String? contentType, List<int> body) {
    if (body.isEmpty) return const {};
    final type = contentType ?? '';
    final looksText =
        type.startsWith('text/') ||
        type.contains('json') ||
        type.contains('x-www-form-urlencoded') ||
        (type.isEmpty && body.first == 0x7B);
    if (!looksText) return const {};
    return {'body': utf8.decode(body, allowMalformed: true)};
  }

  void _traceError(String method, Uri uri, Object error) => _trace?.call(
    TraceEvent(
      channel: TraceChannel.http,
      direction: TraceDirection.internal,
      kind: 'error',
      fields: {'method': method, 'url': uri.toString(), 'error': '$error'},
    ),
  );

  void _traceResponse(
    Uri uri,
    HttpClientResponse response,
    List<int> body,
    Duration elapsed,
  ) => _trace?.call(
    TraceEvent(
      channel: TraceChannel.http,
      direction: TraceDirection.inbound,
      kind: 'response',
      fields: {
        'method': 'GET',
        'url': uri.toString(),
        'status': response.statusCode,
        'headers': _headerMap(response.headers),
        'contentType': response.headers.contentType?.toString(),
        'bodyLength': body.length,
        'elapsedMs': elapsed.inMilliseconds,
        ..._bodyField(response.headers.contentType?.toString(), body),
      },
    ),
  );
}

final class _Reply {
  const new(this.route, this.status, this.contentType, this.headers, this.body);
  final String route;
  final int status;
  final String? contentType;
  final Map<String, String> headers;
  final Uint8List body;
}
