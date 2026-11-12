/// Text for sizes, durations, dates, storages and formats in the library,
/// in the locale of the context.
library;

import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/library/shot.dart';
import 'package:intl/intl.dart';

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// `74 MB`, `8.2 MB`, `1.4 GB`, `640 KB` (decimal units, as the OS file
/// managers show).
String formatBytes(BuildContext context, int bytes) {
  final l10n = context.l10n;
  final locale = _locale(context);
  // One decimal below 10 of a unit, whole numbers above.
  String number(double value) =>
      NumberFormat(value < 10 ? '0.0' : '#,##0', locale).format(value);
  if (bytes < 1000) {
    return l10n.librarySizeBytes(NumberFormat('#,##0', locale).format(bytes));
  }
  if (bytes < 1000 * 1000) {
    return l10n.librarySizeKilobytes(
      NumberFormat('#,##0', locale).format(bytes / 1000),
    );
  }
  if (bytes < 1000 * 1000 * 1000) {
    return l10n.librarySizeMegabytes(number(bytes / 1e6));
  }
  return l10n.librarySizeGigabytes(number(bytes / 1e9));
}

/// `31 MB/s`, `850 KB/s`.
String formatRate(BuildContext context, double bytesPerSecond) =>
    context.l10n.libraryRate(formatBytes(context, bytesPerSecond.round()));

/// `0:14`, `12:03`, `1:02:03`.
String formatDuration(BuildContext context, Duration d) {
  final l10n = context.l10n;
  final locale = _locale(context);
  final plain = NumberFormat('0', locale);
  final padded = NumberFormat('00', locale);
  final seconds = padded.format(d.inSeconds.remainder(60));
  final minutes = d.inMinutes.remainder(60);
  if (d.inHours == 0) {
    return l10n.libraryDurationMinutes(plain.format(minutes), seconds);
  }
  return l10n.libraryDurationHours(
    plain.format(d.inHours),
    padded.format(minutes),
    seconds,
  );
}

/// `Today`, `Yesterday`, the weekday within the past week, the day and
/// month, or with the year in another year.
String formatDay(BuildContext context, DateTime day, DateTime now) {
  final l10n = context.l10n;
  final locale = _locale(context);
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final days = today.difference(d).inHours ~/ 24;
  if (days == 0) return l10n.libraryToday;
  if (days == 1) return l10n.libraryYesterday;
  if (days > 1 && days < 7) return DateFormat.EEEE(locale).format(d);
  if (d.year == now.year) return DateFormat.MMMd(locale).format(d);
  return DateFormat.yMMMd(locale).format(d);
}

/// The day, month and year.
String formatDate(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(_locale(context)).format(d);

/// Hours and minutes, on the 12- or 24-hour clock as the phone is set.
String formatTime(BuildContext context, DateTime t) {
  final locale = _locale(context);
  final format = MediaQuery.alwaysUse24HourFormatOf(context)
      ? DateFormat.Hm(locale)
      : DateFormat.jm(locale);
  return format.format(t);
}

/// [formatDay] with [formatTime].
String formatDayTime(BuildContext context, DateTime t, DateTime now) => context
    .l10n
    .libraryDayTime(formatDay(context, t, now), formatTime(context, t));

/// A shot count, `3`.
String formatCount(BuildContext context, int count) =>
    NumberFormat.decimalPattern(_locale(context)).format(count);

/// `in` → Internal, `sd1` → SD; another storage as the camera names it.
String? storageLabel(BuildContext context, String? storage) =>
    switch (storage) {
      null => null,
      GrStorageId.internal => context.l10n.libraryStorageInternal,
      GrStorageId.sd => context.l10n.libraryStorageSd,
      final s => s.toUpperCase(),
    };

/// `JPEG`, `RAW`, `RAW+JPEG`, `Video`.
String formatLabel(BuildContext context, ShotFormat f) => switch (f) {
  ShotFormat.jpeg => context.l10n.libraryFormatJpeg,
  ShotFormat.raw => context.l10n.libraryFormatRaw,
  ShotFormat.rawJpeg => context.l10n.libraryFormatRawJpeg,
  ShotFormat.video => context.l10n.libraryFormatVideo,
};
