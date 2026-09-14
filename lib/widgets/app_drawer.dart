import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import 'mail_avatar.dart';

/// Navigation drawer: folders, then Settings and Logout.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.selectedFolder,
    required this.onSelectFolder,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final MailFolder selectedFolder;
  final ValueChanged<MailFolder> onSelectFolder;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Row(
                children: [
                  MailAvatar(
                    identity: 'me@kaydet.app',
                    displayName: 'KAYDET',
                    size: 40,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KAYDET',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'me@kaydet.app',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final folder in MailFolder.values)
                        _FolderTile(
                          folder: folder,
                          selected: folder == selectedFolder,
                          onTap: () => onSelectFolder(folder),
                          badgeCount: _badgeCount(repo, folder),
                        ),
                      const Divider(),
                      _SectionTile(
                        icon: LucideIcons.settings,
                        label: 'Settings',
                        onTap: onOpenSettings,
                      ),
                      _SectionTile(
                        icon: LucideIcons.logOut,
                        label: 'Logout',
                        onTap: onLogout,
                      ),
                    ],
                  );
                },
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
    return ListTile(
      onTap: onTap,
      dense: true,
      selected: selected,
      selectedColor: Colors.black,
      selectedTileColor: const Color(0xFFF3F4F6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          ? Badge(
              label: Text('$badgeCount'),
              largeSize: 20,
            )
          : null,
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
    return ListTile(
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, size: 20, color: AppTheme.secondaryText),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14.5,
          color: AppTheme.secondaryText,
        ),
      ),
    );
  }
}