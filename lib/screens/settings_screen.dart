import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_account.dart';
import '../theme/app_theme.dart';
import '../widgets/mail_avatar.dart';
import 'add_account_screen.dart';
import 'settings/account_settings_screen.dart';
import 'settings/interaction_sections.dart';
import 'settings/label_settings.dart';
import 'settings/network_sections.dart';
import 'settings/privacy_sections.dart';
import 'settings/settings_widgets.dart';

export 'settings/account_settings_screen.dart';

/// Settings index: device-wide preferences ("Genel ayarlar") and, below
/// them, one entry per connected account. Everything that belongs to a
/// mailbox — signatures, labels, contacts, folders, notifications, sync,
/// signed-in devices — lives under that account, never in the general list.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<Color> labelColors = kLabelColors;
  static const List<String> labelColorNames = kLabelColorNames;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ayarlar')),
    body: ListenableBuilder(
      listenable: AppConfig.mailRepository,
      builder: (context, _) {
        final accounts = AppConfig.mailRepository.accounts;
        return ListView(
          key: const Key('settings-list'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            SettingsCategoryTile(
              icon: LucideIcons.slidersHorizontal,
              title: 'Genel ayarlar',
              subtitle: 'Görüntü, etkileşim, bildirimler, ağ ve gizlilik',
              onTap: (ctx) => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => const GeneralSettingsScreen(),
                ),
              ),
            ),
            const SettingsSectionHeader('Hesaplar'),
            for (final account in accounts) _AccountTile(account: account),
            SettingsCategoryTile(
              icon: LucideIcons.plus,
              title: 'Hesap ekle',
              subtitle: 'Yeni posta hesabı bağla',
              onTap: (ctx) => Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => const AddAccountScreen()),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});

  final MailAccount account;

  static String subtitleFor(MailAccount account) => switch (account.status) {
    MailAccountStatus.active =>
      'İmza, etiket, kişi, klasör ve bildirim ayarları',
    MailAccountStatus.needsReauthentication =>
      'Bağlantısı kesildi — şifreyi güncelleyin',
    MailAccountStatus.connectionError => 'Bağlantı sorunu',
    MailAccountStatus.disabled => 'Devre dışı',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final needsAttention = account.status != MailAccountStatus.active;
    return ListTile(
      key: ValueKey('settings-account-${account.id}'),
      leading: MailAvatar(
        identity: account.email,
        displayName: account.email,
        size: 36,
      ),
      title: Text(account.email, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleFor(account),
        style: needsAttention
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 18,
        color: colors.secondaryText,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AccountSettingsScreen(accountId: account.id),
        ),
      ),
    );
  }
}

/// Device-wide settings only; account-owned ones are under each account.
class GeneralSettingsScreen extends StatelessWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Genel ayarlar')),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsCategoryTile(
          icon: LucideIcons.palette,
          title: 'Görüntü',
          subtitle: 'Açık, koyu veya sistem teması',
          page: (_) => [AppearanceSection()],
        ),
        SettingsCategoryTile(
          icon: LucideIcons.slidersHorizontal,
          title: 'Etkileşim',
          subtitle: 'Kaydırma, göndermeyi geri alma ve cihaz kişileri',
          page: (_) => [
            SwipeSection(),
            UndoSendSection(),
            DeviceContactsSection(),
          ],
        ),
        SettingsCategoryTile(
          icon: LucideIcons.bell,
          title: 'Bildirimler',
          subtitle: 'Bu cihazda yeni e-posta bildirimleri',
          page: (_) => [NotificationsSection()],
        ),
        SettingsCategoryTile(
          icon: LucideIcons.network,
          title: 'Ağ',
          subtitle: 'Yenileme, ekler ve sunucu',
          page: (_) => [NetworkSection()],
          grouped: false,
        ),
        SettingsCategoryTile(
          icon: LucideIcons.shieldCheck,
          title: 'Gizlilik',
          subtitle: 'Uygulama kilidi, ekran koruması ve bağlantılar',
          page: (_) => [
            CleanTrackingQueriesSection(),
            BiometricLockSection(),
            ScreenProtectionSection(),
          ],
        ),
      ],
    ),
  );
}
