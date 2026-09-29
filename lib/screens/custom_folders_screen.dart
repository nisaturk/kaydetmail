import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'folder_manager_screen.dart';

/// Drawer entry for "Klasörleri yönet": goes straight to the folder manager
/// of the active account, or of the only account; with several accounts in
/// the unified mailbox it first asks which account's folders to manage.
class CustomFoldersScreen extends StatelessWidget {
  const CustomFoldersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    final accounts = repo.accounts;
    final direct =
        repo.activeAccountId ??
        (accounts.length == 1 ? accounts.single.id : null);
    if (direct != null) return FolderManagerScreen(accountId: direct);
    return Scaffold(
      appBar: AppBar(title: const Text('Klasörleri yönet')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Hangi hesabın klasörleri yönetilsin?'),
          ),
          for (final account in accounts)
            ListTile(
              key: ValueKey('manage-folders-${account.id}'),
              leading: Icon(
                LucideIcons.mail,
                color: AppTheme.colors(context).secondaryText,
              ),
              title: Text(account.email),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FolderManagerScreen(accountId: account.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
