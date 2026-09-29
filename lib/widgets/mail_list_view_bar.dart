import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/mail_list_view.dart';
import '../theme/app_theme.dart';

/// Filter chips plus a sort menu shown above a mail list.
class MailListViewBar extends StatelessWidget {
  const MailListViewBar({
    super.key,
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  final MailListFilter filter;
  final MailListSort sort;
  final ValueChanged<MailListFilter> onFilterChanged;
  final ValueChanged<MailListSort> onSortChanged;

  static String filterLabel(MailListFilter filter) => switch (filter) {
    MailListFilter.all => 'Tümü',
    MailListFilter.unread => 'Okunmamış',
    MailListFilter.starred => 'Yıldızlı',
    MailListFilter.attachments => 'Ekli',
  };

  static String sortLabel(MailListSort sort) => switch (sort) {
    MailListSort.newest => 'En yeni önce',
    MailListSort.oldest => 'En eski önce',
    MailListSort.unreadFirst => 'Okunmamışlar önce',
    MailListSort.sender => 'Gönderene göre (A-Z)',
    MailListSort.subject => 'Konuya göre (A-Z)',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const Key('mail-filter-chips'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  for (final option in MailListFilter.values) ...[
                    ChoiceChip(
                      key: Key('mail-filter-${option.name}'),
                      label: Text(filterLabel(option)),
                      selected: filter == option,
                      showCheckmark: false,
                      onSelected: (_) => onFilterChanged(option),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<MailListSort>(
            key: const Key('mail-sort-menu'),
            tooltip: 'Sırala',
            icon: Icon(
              LucideIcons.arrowUpDown,
              size: 20,
              color: sort == MailListSort.newest
                  ? colors.secondaryText
                  : Theme.of(context).colorScheme.onSurface,
            ),
            initialValue: sort,
            onSelected: onSortChanged,
            itemBuilder: (context) => [
              for (final option in MailListSort.values)
                CheckedPopupMenuItem(
                  key: Key('mail-sort-${option.name}'),
                  value: option,
                  checked: option == sort,
                  child: Text(sortLabel(option)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
