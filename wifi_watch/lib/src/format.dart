// Human-readable sizes, speeds and times.

String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  final digits = i == 0 || v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}

/// Bytes per second as bits per second, the way speeds are usually quoted.
String formatSpeed(double bytesPerSecond) {
  final bits = bytesPerSecond * 8;
  if (bits >= 1e6) return '${(bits / 1e6).toStringAsFixed(bits >= 1e8 ? 0 : 1)} Mbps';
  if (bits >= 1e3) return '${(bits / 1e3).toStringAsFixed(0)} Kbps';
  return '${bits.toStringAsFixed(0)} bps';
}

String formatAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatWeekday(DateTime d) => _weekdays[d.weekday - 1];
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String formatDateTime(DateTime d) =>
    '${formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
