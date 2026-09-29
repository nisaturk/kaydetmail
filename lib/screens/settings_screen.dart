import '../utils/insets.dart';

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
import '../l10n/l10n.dart';

/// Settings index: device-wide preferences ("Genel ayarlar") and, below
/// them, one entry per connected account. Everything that belongs to a
/// mailbox — signatures, labels, contacts, folders, notifications, sync,
/// signed-in devices — lives under that account, never in the general list.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<Color> labelColors = kLabelColors;
  static final List<String> labelColorNames = kLabelColorNames;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(l10nNow.settings)),
    body: ListenableBuilder(
      listenable: AppConfig.mailRepository,
      builder: (context, _) {
        final accounts = AppConfig.mailRepository.accounts;
        return ListView(
          key: const Key('settings-list'),
          padding: withBottomInset(
            context,
            const EdgeInsets.symmetric(vertical: 8),
          ),
          children: [
            SettingsCategoryTile(
              icon: LucideIcons.slidersHorizontal,
              title: l10nNow.generalSettings,
              subtitle: l10nNow.appearanceInteractionNotificationsNetworkAnd,
              onTap: (ctx) => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => const GeneralSettingsScreen(),
                ),
              ),
            ),
            SettingsSectionHeader(l10nNow.accounts),
            for (final account in accounts) _AccountTile(account: account),
            SettingsCategoryTile(
              icon: LucideIcons.plus,
              title: l10nNow.addAccount,
              subtitle: l10nNow.connectANewMailAccount,
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
    MailAccountStatus.active => l10nNow.signatureLabelContactFolderAnd,
    MailAccountStatus.needsReauthentication =>
      l10nNow.disconnectedUpdateThePassword,
    MailAccountStatus.connectionError => l10nNow.connectionProblem,
    MailAccountStatus.disabled => l10nNow.disabled,
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
    appBar: AppBar(title: Text(l10nNow.generalSettings)),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsCategoryTile(
          icon: LucideIcons.palette,
          title: l10nNow.appearance,
          subtitle: l10nNow.lightDarkOrSystemTheme,
          page: (_) => [AppearanceSection()],
        ),
        SettingsCategoryTile(
          icon: LucideIcons.languages,
          title: l10nNow.language,
          subtitle: l10nNow.tRkEOrEnglish,
          page: (_) => [LanguageSection()],
        ),
        SettingsCategoryTile(
          icon: LucideIcons.slidersHorizontal,
          title: l10nNow.interaction,
          subtitle: l10nNow.swipeUndoSendAndDevice,
          page: (_) => [
            SwipeSection(),
            UndoSendSection(),
            DeviceContactsSection(),
          ],
        ),
        SettingsCategoryTile(
          icon: LucideIcons.bell,
          title: l10nNow.notifications,
          subtitle: l10nNow.newEmailNotificationsOnThis,
          page: (_) => [NotificationsSection()],
        ),
        SettingsCategoryTile(
          icon: LucideIcons.network,
          title: l10nNow.network,
          subtitle: l10nNow.refreshAttachmentsAndServer,
          page: (_) => [NetworkSection()],
          grouped: false,
        ),
        SettingsCategoryTile(
          icon: LucideIcons.shieldCheck,
          title: l10nNow.privacy,
          subtitle: l10nNow.appLockScreenProtectionAnd,
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
