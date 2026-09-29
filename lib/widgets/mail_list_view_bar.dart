import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/mail_list_view.dart';
import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

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
    MailListFilter.all => l10nNow.all,
    MailListFilter.unread => l10nNow.unread4,
    MailListFilter.starred => l10nNow.starred2,
    MailListFilter.attachments => l10nNow.attachments3,
  };

  static String sortLabel(MailListSort sort) => switch (sort) {
    MailListSort.newest => l10nNow.newestFirst,
    MailListSort.oldest => l10nNow.oldestFirst,
    MailListSort.unreadFirst => l10nNow.unreadFirst,
    MailListSort.sender => l10nNow.bySenderAZ,
    MailListSort.subject => l10nNow.bySubjectAZ,
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
            tooltip: l10nNow.sort,
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
