import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import 'mail_avatar.dart';

/// Drawer'dan açılabilen uygulama hedefleri. Klasörler ayrı seçilir
/// ([onSelectFolder]); bu liste menüdeki alt bölümü tek tablodan üretir.
enum DrawerDestination {
  accounts,
  scheduled,
  reminders,
  outbox,
  customFolders,
  settings,
}

/// Hedefin menüdeki karşılığı: ikon + Türkçe etiket tek tabloda.
extension DrawerDestinationMeta on DrawerDestination {
  IconData get icon => switch (this) {
    DrawerDestination.accounts => LucideIcons.users,
    DrawerDestination.scheduled => LucideIcons.calendarClock,
    DrawerDestination.reminders => LucideIcons.bellRing,
    DrawerDestination.outbox => LucideIcons.send,
    DrawerDestination.customFolders => LucideIcons.folder,
    DrawerDestination.settings => LucideIcons.settings,
  };

  String get label => switch (this) {
    DrawerDestination.accounts => 'Hesaplar',
    DrawerDestination.scheduled => 'Zamanlanmış Gönderimler',
    DrawerDestination.reminders => 'Yanıt Takibi',
    DrawerDestination.outbox => 'Giden Kutusu',
    DrawerDestination.customFolders => 'Diğer Klasörler',
    DrawerDestination.settings => 'Ayarlar',
  };
}

/// Navigation drawer: klasörler üstte, uygulama hedefleri altta.
///
/// Sık kullanılan klasörler doğrudan listelenir; Çöp/Spam/Arşiv
/// "Diğer" başlığı altında toplanır ki menü ilk bakışta kısa kalsın.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.selectedFolder,
    required this.onSelectFolder,
    required this.onLogout,
    required this.onOpenDestination,
  });

  final MailFolder selectedFolder;
  final ValueChanged<MailFolder> onSelectFolder;
  final VoidCallback onLogout;
  final ValueChanged<DrawerDestination> onOpenDestination;

  /// İlk bakışta görünen klasörler; kalanı "Diğer" altında.
  static const _primaryFolders = [
    MailFolder.inbox,
    MailFolder.starred,
    MailFolder.snoozed,
    MailFolder.sent,
    MailFolder.drafts,
  ];

  static const _secondaryFolders = [
    MailFolder.trash,
    MailFolder.spam,
    MailFolder.archive,
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                        Text(
                          'KAYDET',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          AppConfig.mailRepository.currentUser,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.colors(context).secondaryText,
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
                      const _MenuHeading('Klasörler'),
                      for (final folder in _primaryFolders)
                        _FolderTile(
                          folder: folder,
                          selected: folder == selectedFolder,
                          onTap: () => onSelectFolder(folder),
                          badgeCount: _badgeCount(repo, folder),
                        ),
                      ExpansionTile(
                        shape: const Border(),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 24),
                        childrenPadding: EdgeInsets.zero,
                        leading: Icon(
                          LucideIcons.archive,
                          size: 20,
                          color: AppTheme.colors(context).secondaryText,
                        ),
                        title: Text(
                          'Diğer',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: AppTheme.colors(context).secondaryText,
                          ),
                        ),
                        children: [
                          for (final folder in _secondaryFolders)
                            _FolderTile(
                              folder: folder,
                              selected: folder == selectedFolder,
                              onTap: () => onSelectFolder(folder),
                              badgeCount: _badgeCount(repo, folder),
                            ),
                        ],
                      ),
                      const _MenuHeading('Uygulama'),
                      for (final destination in DrawerDestination.values)
                        _SectionTile(
                          icon: destination.icon,
                          label: destination.label,
                          onTap: () => onOpenDestination(destination),
                        ),
                    ],
                  );
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SectionTile(
                icon: LucideIcons.logOut,
                label: 'Çıkış Yap',
                onTap: onLogout,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _badgeCount(MailRepository repo, MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
      case MailFolder.drafts:
      case MailFolder.spam:
        return repo.unreadCount(folder);
      case MailFolder.sent:
      case MailFolder.starred:
      case MailFolder.trash:
      case MailFolder.archive:
        return 0;
      case MailFolder.snoozed:
        return repo.getEmailsInFolder(MailFolder.snoozed).length;
    }
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.colors(context).secondaryText,
        ),
      ),
    );
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
    final colors = AppTheme.colors(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedColor: onSurface,
        selectedTileColor: colors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          folder.icon,
          size: 20,
          color: selected ? onSurface : colors.secondaryText,
        ),
        title: Text(
          folder.label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? onSurface : colors.secondaryText,
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
    final secondaryText = AppTheme.colors(context).secondaryText;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 20, color: secondaryText),
        title: Text(
          label,
          style: TextStyle(fontSize: 14.5, color: secondaryText),
        ),
      ),
    );
  }
}
