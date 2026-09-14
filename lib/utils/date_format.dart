/// Compact, human friendly timestamp used on mail list rows.
///
/// Recent emails show minutes/hours or clock time, older ones show a weekday
/// or a short date.
String formatMailTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(time);

  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
  if (diff.inDays < 7) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[time.weekday - 1];
  }
  return '${time.day}/${time.month}/${time.year}';
}

/// Long form date used on the mail detail screen, e.g. "Mon, 14 Sep 2026,
/// 14:30".
String formatMailDateFull(DateTime time) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '${weekdays[time.weekday - 1]}, ${time.day} '
      '${months[time.month - 1]} ${time.year}, $hh:$mm';
}