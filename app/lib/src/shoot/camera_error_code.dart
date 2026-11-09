import 'dart:async';

import 'package:gr_camera/gr_camera.dart';

/// A short technical code for [error], for the parentheses after a message
/// that says what the camera did not do: the camera's `errCode`, an HTTP
/// status or a Bluetooth error category. Null when the error has none; the
/// full error is in the camera layer's trace.
String? cameraErrorCode(Object error) => switch (error) {
  GrApiException(:final errCode) => '$errCode',
  GrHttpException(httpStatus: final status?) => 'HTTP $status',
  BleException(:final code) => code.name,
  GrSessionException(cause: final cause?) => cameraErrorCode(cause),
  TimeoutException() => 'timeout',
  _ => null,
};
