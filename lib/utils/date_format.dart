import '../l10n/l10n.dart';
import '../state/app_settings_controller.dart';

/// Compact, human friendly timestamp used on mail list rows.
///
/// Recent emails show minutes/hours or clock time, older ones show a weekday
/// or a short date, in the app language.
String formatMailTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(time);

  if (diff.inMinutes < 1) return l10nNow.now;
  if (diff.inMinutes < 60) return l10nNow.minAgo(diff.inMinutes);
  final today = DateTime(n.year, n.month, n.day);
  final date = DateTime(time.year, time.month, time.day);
  if (date == today) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
  if (date == today.subtract(const Duration(days: 1))) return l10nNow.yesterday;
  if (n.difference(date).inDays < 7) {
    return _names.weekdays[time.weekday - 1];
  }
  return '${time.day}.${time.month}.${time.year}';
}

/// Long form date used on the mail detail screen, e.g. "Pzt, 14 Eyl 2026,
/// 14:30".
String formatMailDateFull(DateTime time) {
  final names = _names;
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '${names.weekdays[time.weekday - 1]}, ${time.day} '
      '${names.months[time.month - 1]} ${time.year}, $hh:$mm';
}

typedef _DateNames = ({List<String> weekdays, List<String> months});

const _turkishNames = (
  weekdays: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'],
  months: [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ],
);

const _englishNames = (
  weekdays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  months: [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ],
);

_DateNames get _names =>
    AppSettingsController.instance.locale.languageCode == 'en'
    ? _englishNames
    : _turkishNames;
