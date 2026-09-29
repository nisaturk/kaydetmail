import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

/// Bottom sheet offering quick snooze presets plus a custom date/time
/// picker. Returns the chosen deadline (local time), or null if the user
/// dismissed it without picking one.
Future<DateTime?> showSnoozePicker(BuildContext context) {
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (ctx) => const _SnoozePickerSheet(),
  );
}

class _SnoozePickerSheet extends StatelessWidget {
  const _SnoozePickerSheet();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final colors = AppTheme.colors(context);
    final presets = <({String label, DateTime value})>[
      (label: l10nNow.in1Hour, value: now.add(const Duration(hours: 1))),
      (label: l10nNow.thisEvening600Pm, value: _todayAt(now, 18)),
      (
        label: l10nNow.tomorrowMorning900Am,
        value: _todayAt(now, 9).add(const Duration(days: 1)),
      ),
      (label: l10nNow.nextWeekMonday900, value: _nextMonday9am(now)),
    ];
    // Short landscape + large text can exceed the sheet height — scroll
    // instead of overflowing (probe: 640x320 @ 1.3x).
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10nNow.snooze,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final preset in presets)
              if (preset.value.isAfter(now))
                ListTile(
                  leading: Icon(LucideIcons.clock, color: colors.secondaryText),
                  title: Text(preset.label),
                  onTap: () => Navigator.of(context).pop(preset.value),
                ),
            ListTile(
              leading: Icon(
                LucideIcons.calendarClock,
                color: colors.secondaryText,
              ),
              title: Text(l10nNow.chooseDateAndTime),
              onTap: () async {
                final picked = await _pickCustom(context, now);
                if (picked != null && context.mounted) {
                  Navigator.of(context).pop(picked);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickCustom(BuildContext context, DateTime now) async {
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return null;
    // Same-day picks can still land in the past (e.g. today + an hour
    // that's already gone) — re-prompt for the time instead of accepting
    // a snooze deadline that would expire the instant it's set.
    while (true) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );
      if (time == null || !context.mounted) return null;
      final candidate = combineSnoozeDateTime(
        date: date,
        time: time,
        now: DateTime.now(),
      );
      if (candidate != null) return candidate;
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10nNow.theChosenTimeIsIn)));
    }
  }
}

/// Combines a picked date + time into a deadline, or null when the result
/// isn't strictly after [now] — a picked date of "today" can otherwise pair
/// with an hour that has already passed. Extracted so the past-deadline
/// rejection is testable without driving the date/time picker dialogs.
DateTime? combineSnoozeDateTime({
  required DateTime date,
  required TimeOfDay time,
  required DateTime now,
}) {
  final candidate = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  return candidate.isAfter(now) ? candidate : null;
}

DateTime _todayAt(DateTime now, int hour) =>
    DateTime(now.year, now.month, now.day, hour);

DateTime _nextMonday9am(DateTime now) {
  final daysUntilMonday = (DateTime.monday - now.weekday) % 7;
  final offset = daysUntilMonday == 0 ? 7 : daysUntilMonday;
  final day = _todayAt(now, 9).add(Duration(days: offset));
  return day;
}
