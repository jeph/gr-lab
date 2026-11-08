/// Text for sizes, durations and dates in the library.
library;

/// `74 MB`, `8.2 MB`, `1.4 GB`, `640 KB` (decimal units, as the OS file
/// managers show).
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} KB';
  if (bytes < 1000 * 1000 * 1000) {
    final mb = bytes / 1e6;
    return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
  }
  final gb = bytes / 1e9;
  return gb < 10 ? '${gb.toStringAsFixed(1)} GB' : '${gb.round()} GB';
}

/// `31 MB/s`, `850 KB/s`.
String formatRate(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

/// `0:14`, `12:03`, `1:02:03`.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', //
  'Saturday', 'Sunday',
];

/// `Today`, `Yesterday`, `Wednesday` within the past week, `3 Nov`, or
/// `3 Nov 2025` in another year.
String formatDay(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final days = today.difference(d).inHours ~/ 24;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return _weekdays[d.weekday - 1];
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// `14:22`.
String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `Today 14:22`, `3 Nov 14:22`.
String formatDayTime(DateTime t, DateTime now) =>
    '${formatDay(t, now)} ${formatTime(t)}';
