import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import 'mail_avatar.dart';

/// Navigation drawer: folders, then Hesaplar, Settings and Logout.
///
/// Mailbox switching happens from the inbox title (one clear mechanism) — the
/// drawer only manages folders and app-level destinations.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.selectedFolder,
    required this.onSelectFolder,
    required this.onLogout,
    required this.onOpenSettings,
    required this.onOpenAccounts,
  });

  final MailFolder selectedFolder;
  final ValueChanged<MailFolder> onSelectFolder;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAccounts;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Row(
                children: [
                  MailAvatar(
                    identity: AppConfig.mailRepository.currentUser,
                    displayName: 'KAYDET',
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'KAYDET',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          AppConfig.mailRepository.currentUser,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListenableBuilder(
                listenable: AppConfig.mailRepository,
                builder: (context, _) {
                  final repo = AppConfig.mailRepository;
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final folder in MailFolder.values)
                        _FolderTile(
                          folder: folder,
                          selected: folder == selectedFolder,
                          onTap: () => onSelectFolder(folder),
                          badgeCount: _badgeCount(repo, folder),
                        ),
                    ],
                  );
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  _SectionTile(
                    icon: LucideIcons.users,
                    label: 'Hesaplar',
                    onTap: onOpenAccounts,
                  ),
                  _SectionTile(
                    icon: LucideIcons.settings,
                    label: 'Ayarlar',
                    onTap: onOpenSettings,
                  ),
                  _SectionTile(
                    icon: LucideIcons.logOut,
                    label: 'Çıkış Yap',
                    onTap: onLogout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _badgeCount(MailRepository repo, MailFolder folder) {
    final emails = repo.getEmailsInFolder(folder);
    switch (folder) {
      case MailFolder.inbox:
      case MailFolder.drafts:
      case MailFolder.spam:
        return emails.where((e) => !e.isRead).length;
      case MailFolder.sent:
      case MailFolder.pinned:
      case MailFolder.trash:
      case MailFolder.archive:
        return 0;
    }
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.selected,
    required this.onTap,
    required this.badgeCount,
  });

  final MailFolder folder;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedColor: Colors.black,
        selectedTileColor: const Color(0xFFF3F4F6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          folder.icon,
          size: 20,
          color: selected ? Colors.black : AppTheme.secondaryText,
        ),
        title: Text(
          folder.label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.black : AppTheme.secondaryText,
          ),
        ),
        trailing: badgeCount > 0
            ? Badge(label: Text('$badgeCount'), largeSize: 20)
            : null,
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 20, color: AppTheme.secondaryText),
        title: Text(
          label,
          style: const TextStyle(fontSize: 14.5, color: AppTheme.secondaryText),
        ),
      ),
    );
  }
}
