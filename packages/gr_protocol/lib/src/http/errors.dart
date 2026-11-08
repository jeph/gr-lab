/// Failures reported by the camera's HTTP API. Transport failures surface as
/// the `dart:io`/`dart:async` exceptions that caused them (`SocketException`,
/// `HttpException`, `TimeoutException`).
sealed class GrHttpException implements Exception {
  const GrHttpException(this.route, this.httpStatus);

  /// `METHOD /path` of the failed request, e.g. `GET /v1/props`.
  final String route;

  /// HTTP status line code, or `null` when no response head was received.
  final int? httpStatus;
}

/// The camera answered with a JSON envelope whose `errCode` is not 200.
///
/// Both apps treat `errCode` as the authority, not the HTTP status
/// (docs/protocol/remote-shooting.md §0 item 3, docs/protocol/http-api.md §8).
final class GrApiException extends GrHttpException {
  const GrApiException({
    required this.errCode,
    required String route,
    required int? httpStatus,
    this.errMsg,
    this.reason,
    this.body = const {},
  }) : super(route, httpStatus);

  final int errCode;
  final String? errMsg;

  /// `detail.reason`, sent by firmware routes (e.g. `err_fw_same`).
  final String? reason;

  /// The complete parsed envelope, unknown keys included.
  final Map<String, Object?> body;

  /// Firmware-update interpretation of this error
  /// (docs/protocol/http-api.md §7 "Firmware error mapping").
  GrFirmwareRejection get firmwareRejection =>
      classifyFirmwareRejection(errCode, reason);

  @override
  String toString() =>
      'GrApiException: $route returned errCode $errCode'
      '${errMsg == null ? '' : ' ($errMsg)'}'
      '${reason == null ? '' : ' reason=$reason'}'
      '${httpStatus == null ? '' : ' [HTTP $httpStatus]'}';
}

/// Non-200 HTTP status without a parsable `errCode` envelope (GR WORLD maps
/// these to "GET/PUT/POST error" with the status, http-api.md §1).
final class GrHttpStatusException extends GrHttpException {
  const GrHttpStatusException({
    required String route,
    required int httpStatus,
    this.bodyText = '',
  }) : super(route, httpStatus);

  final String bodyText;

  @override
  String toString() =>
      'GrHttpStatusException: $route returned HTTP $httpStatus'
      '${bodyText.isEmpty ? '' : ': ${_clip(bodyText)}'}';
}

/// A 200 response whose body does not have the documented shape (not JSON
/// where JSON is required, or a download shorter than its Content-Length).
final class GrMalformedResponseException extends GrHttpException {
  const GrMalformedResponseException({
    required String route,
    required int? httpStatus,
    required this.issue,
    this.bodyText = '',
  }) : super(route, httpStatus);

  final String issue;
  final String bodyText;

  @override
  String toString() =>
      'GrMalformedResponseException: $route: $issue'
      '${bodyText.isEmpty ? '' : ': ${_clip(bodyText)}'}';
}

String _clip(String s) => s.length <= 200 ? s : '${s.substring(0, 200)}…';

/// GR WORLD's firmware-update error classes (http-api.md §7, `0x854ea8`).
enum GrFirmwareRejection {
  /// errCode 200: not a rejection.
  none,

  /// 400 `err_fw_same`: the camera already runs this version.
  sameVersion,

  /// 400 `err_fw_old`: the file is older than the installed firmware.
  olderVersion,

  /// 400 with any other reason.
  badRequest,

  /// 412 `battery_too_low`.
  batteryTooLow,

  /// 412 with any other reason.
  preconditionFailed,

  /// Any other errCode.
  unexpected,
}

GrFirmwareRejection classifyFirmwareRejection(int errCode, String? reason) =>
    switch ((errCode, reason)) {
      (200, _) => GrFirmwareRejection.none,
      (400, 'err_fw_same') => GrFirmwareRejection.sameVersion,
      (400, 'err_fw_old') => GrFirmwareRejection.olderVersion,
      (400, _) => GrFirmwareRejection.badRequest,
      (412, 'battery_too_low') => GrFirmwareRejection.batteryTooLow,
      (412, _) => GrFirmwareRejection.preconditionFailed,
      _ => GrFirmwareRejection.unexpected,
    };
