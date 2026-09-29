import '../../utils/insets.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../models/mail_account.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/mail_avatar.dart';
import '../folder_manager_screen.dart';
import '../login_screen.dart';
import '../notification_settings_screen.dart';
import '../signatures_screen.dart';
import '../sync_status_screen.dart';
import '../templates_screen.dart';
import '../trusted_senders_screen.dart';
import 'contact_settings.dart';
import 'label_settings.dart';
import 'privacy_sections.dart';
import 'settings_widgets.dart';

/// Everything that belongs to one mailbox, in one place: identity and
/// status, storage, writing (signatures, reusable texts, labels, contacts),
/// mailbox (folders, sync, notifications, remote-image trust) and security
/// (signed-in devices), plus sign-out and removal.
class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key, required this.accountId});

  final String accountId;

  void _push(BuildContext context, WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final account = repo.getAccount(accountId);
        if (account == null) {
          // Removed or signed out while this page was open.
          return Scaffold(
            appBar: AppBar(title: const Text('Hesap ayarları')),
            body: const Center(child: Text('Hesap artık bağlı değil.')),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(account.email)),
          body: ListView(
            padding: withBottomInset(
              context,
              const EdgeInsets.symmetric(vertical: 8),
            ),
            children: [
              _AccountHeader(account: account),
              AccountQuotaSection(accountId: accountId),
              const SettingsSectionHeader('E-posta yazma'),
              SettingsCategoryTile(
                icon: LucideIcons.penLine,
                title: 'İmzalar',
                subtitle: 'E-posta imzalarını oluştur ve varsayılanını seç',
                onTap: (ctx) =>
                    _push(ctx, (_) => SignaturesScreen(accountId: accountId)),
              ),
              SettingsCategoryTile(
                icon: LucideIcons.text,
                title: 'Hazır metinler',
                subtitle: 'Tekrar kullanılan konu ve metinler',
                onTap: (ctx) =>
                    _push(ctx, (_) => TemplatesScreen(accountId: accountId)),
              ),
              SettingsCategoryTile(
                icon: LucideIcons.tag,
                title: 'Etiketler',
                subtitle: 'Etiket oluştur, düzenle, sil',
                page: (_) => [LabelsSection(accountId: accountId)],
              ),
              SettingsCategoryTile(
                icon: LucideIcons.bookUser,
                title: 'Kişiler',
                subtitle: 'Yazarken önerilecek kişiler',
                page: (_) => [ContactsSection(accountId: accountId)],
              ),
              const SettingsSectionHeader('Posta kutusu'),
              SettingsCategoryTile(
                icon: LucideIcons.folder,
                title: 'Klasörler',
                subtitle: 'Klasör ağacı, roller ve eşitleme',
                onTap: (ctx) => _push(
                  ctx,
                  (_) => FolderManagerScreen(accountId: accountId),
                ),
              ),
              SettingsCategoryTile(
                icon: LucideIcons.refreshCw,
                title: 'Eşitleme',
                subtitle: 'Klasör bazlı durum ve eşitlenecek klasörler',
                onTap: (ctx) =>
                    _push(ctx, (_) => SyncStatusScreen(accountId: accountId)),
              ),
              SettingsCategoryTile(
                icon: LucideIcons.bellRing,
                title: 'Bildirimler',
                subtitle: 'Klasör kapsamı ve kilit ekranı gizliliği',
                onTap: (ctx) => _push(
                  ctx,
                  (_) => NotificationSettingsScreen(accountId: accountId),
                ),
              ),
              SettingsCategoryTile(
                icon: LucideIcons.image,
                title: 'Kayıtlı görsel tercihleri',
                subtitle: 'Güvenilir gönderici ve alan adları',
                onTap: (ctx) => _push(
                  ctx,
                  (_) => TrustedSendersScreen(accountId: accountId),
                ),
              ),
              const SettingsSectionHeader('Güvenlik'),
              SettingsCategoryTile(
                icon: LucideIcons.smartphone,
                title: 'Bağlı cihazlar',
                subtitle: 'Bu hesaba giriş yapmış cihazlar ve oturumlar',
                page: (_) => [SessionsSection(accountId: accountId)],
              ),
              const SettingsSectionHeader('Hesap'),
              _AccountActions(account: account),
            ],
          ),
        );
      },
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});

  final MailAccount account;

  static String? statusLabel(MailAccountStatus status) => switch (status) {
    MailAccountStatus.active => null,
    MailAccountStatus.needsReauthentication => 'Bağlantısı kesildi',
    MailAccountStatus.connectionError => 'Bağlantı sorunu',
    MailAccountStatus.disabled => 'Devre dışı',
  };

  Future<void> _reconnect(BuildContext context) async {
    final repo = AppConfig.mailRepository;
    // reconnect always targets the active mailbox: make this one active first.
    await repo.setActiveAccount(account.id);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LoginScreen(reconnect: true, initialEmail: account.email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final status = statusLabel(account.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          MailAvatar(
            identity: account.email,
            displayName: account.email,
            size: 48,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  account.provider.label,
                  style: TextStyle(color: colors.secondaryText),
                ),
                if (status != null)
                  Text(
                    status,
                    key: const Key('account-status'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (account.status == MailAccountStatus.needsReauthentication)
            FilledButton.tonal(
              key: const Key('reconnect-account'),
              onPressed: () => _reconnect(context),
              child: const Text('Şifreyi güncelle'),
            ),
        ],
      ),
    );
  }
}

/// Sign out of this device / remove the account. Removal deletes the
/// mailbox connection on the server, so it asks first and is unavailable for
/// the last account (use "Çıkış yap" then).
class _AccountActions extends StatelessWidget {
  const _AccountActions({required this.account});

  final MailAccount account;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    final destructive = AppTheme.colors(context).destructive;
    final canRemove = repo.accounts.length > 1;
    return Column(
      children: [
        ListTile(
          key: const Key('sign-out-account'),
          leading: Icon(LucideIcons.logOut, size: 22, color: destructive),
          title: const Text('Bu cihazdan çıkış yap'),
          subtitle: const Text(
            'Hesap sunucuda kalır; yalnızca bu cihazdaki oturum ve veriler silinir.',
          ),
          onTap: () async {
            if (!await _confirm(
              context,
              title: 'Çıkış yapılsın mı?',
              message:
                  '${account.email} bu cihazdan çıkarılacak. Sunucudaki hesap ve e-postalar silinmez.',
              action: 'Çıkış yap',
            )) {
              return;
            }
            if (!context.mounted) return;
            final navigator = Navigator.of(context);
            await _run(context, () async {
              await repo.signOutAccount(account.id);
              if (repo.isLoggedIn) navigator.popUntil((r) => r.isFirst);
            });
          },
        ),
        if (canRemove)
          ListTile(
            key: const Key('remove-account'),
            leading: Icon(LucideIcons.trash2, size: 22, color: destructive),
            title: const Text('Hesabı kaldır'),
            subtitle: const Text(
              'Bağlantıyı sunucudan siler; e-postalar bu uygulamadan kaldırılır.',
            ),
            onTap: () async {
              if (!await _confirm(
                context,
                title: 'Hesap kaldırılsın mı?',
                message:
                    '${account.email} kaldırılacak ve bu hesaba ait e-postalar '
                    'uygulamadan silinecek. Emin misiniz?',
                action: 'Kaldır',
              )) {
                return;
              }
              if (!context.mounted) return;
              final navigator = Navigator.of(context);
              await _run(context, () async {
                await repo.removeAccount(account.id);
                navigator.popUntil((r) => r.isFirst);
              });
            },
          ),
      ],
    );
  }
}

/// Mailbox storage usage for one account. Refreshes on open and renders
/// nothing while the quota is unknown or the server has no QUOTA support.
class AccountQuotaSection extends StatefulWidget {
  const AccountQuotaSection({super.key, required this.accountId});

  final String accountId;

  @override
  State<AccountQuotaSection> createState() => _AccountQuotaSectionState();
}

class _AccountQuotaSectionState extends State<AccountQuotaSection> {
  @override
  void initState() {
    super.initState();
    unawaited(AppConfig.mailRepository.refreshQuota(widget.accountId));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final quota = repo.accounts
            .where((item) => item.id == widget.accountId)
            .firstOrNull
            ?.quota;
        if (quota == null) return const SizedBox.shrink();
        final colors = AppTheme.colors(context);
        return ListTile(
          key: const Key('account-quota'),
          leading: Icon(
            LucideIcons.hardDrive,
            size: 22,
            color: colors.secondaryText,
          ),
          title: const Text('Depolama'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatStorageSize(quota.usedBytes)} / '
                '${formatStorageSize(quota.limitBytes)} kullanılıyor '
                '(%${quota.usedPercent})',
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: quota.usedFraction,
                semanticsLabel: 'Depolama kullanımı',
                semanticsValue: '${quota.usedPercent}',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Binary-unit size with a Turkish decimal comma: `512 KB`, `1,5 GB`, `15 GB`.
@visibleForTesting
String formatStorageSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  var text = unit == 0 || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
  if (text.endsWith(',0')) text = text.substring(0, text.length - 2);
  return '$text ${units[unit]}';
}
