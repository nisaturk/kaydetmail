import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

Future<DateTime?> showReplyReminderPicker(BuildContext context) {
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (ctx) => const _ReplyReminderPickerSheet(),
  );
}

class _ReplyReminderPickerSheet extends StatelessWidget {
  const _ReplyReminderPickerSheet();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final colors = AppTheme.colors(context);
    final presets = <({String label, DateTime value})>[
      (label: '1 gün sonra', value: now.add(const Duration(days: 1))),
      (label: '3 gün sonra', value: now.add(const Duration(days: 3))),
      (label: '1 hafta sonra', value: now.add(const Duration(days: 7))),
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Yanıt gelmezse hatırlat',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          for (final preset in presets)
            ListTile(
              leading: Icon(LucideIcons.bellRing, color: colors.secondaryText),
              title: Text(preset.label),
              onTap: () => Navigator.of(context).pop(preset.value),
            ),
          ListTile(
            leading: Icon(
              LucideIcons.calendarClock,
              color: colors.secondaryText,
            ),
            title: const Text('Tarih ve saat seç'),
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
    );
  }

  Future<DateTime?> _pickCustom(BuildContext context, DateTime now) async {
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return null;
    while (true) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );
      if (time == null || !context.mounted) return null;
      final candidate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (candidate.isAfter(DateTime.now())) return candidate;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen ileri bir tarih ve saat seçin.'),
          ),
        );
      }
    }
  }
}
