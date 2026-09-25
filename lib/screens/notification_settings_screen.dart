import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/account_notification_settings.dart';
import '../models/mail_account.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final Map<String, AccountNotificationSettings> _settings = {};
  final Map<String, Object> _errors = {};
  final Set<String> _loading = {};
  final Set<String> _saving = {};

  List<MailAccount> get _accounts => AppConfig.mailRepository.accounts;

  @override
  void initState() {
    super.initState();
    for (final account in _accounts) {
      _load(account.id);
    }
  }

  Future<void> _load(String accountId) async {
    setState(() {
      _loading.add(accountId);
      _errors.remove(accountId);
    });
    try {
      final settings = await AppConfig.mailRepository.getNotificationSettings(
        accountId,
      );
      if (!mounted) return;
      setState(() => _settings[accountId] = settings);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors[accountId] = error);
    } finally {
      if (mounted) setState(() => _loading.remove(accountId));
    }
  }

  Future<void> _save(
    String accountId,
    AccountNotificationSettings settings,
  ) async {
    if (_saving.contains(accountId)) return;
    setState(() => _saving.add(accountId));
    try {
      final saved = await AppConfig.mailRepository.updateNotificationSettings(
        accountId,
        settings,
      );
      if (!mounted) return;
      setState(() => _settings[accountId] = saved);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _saving.remove(accountId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hesap bildirimleri')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bu ayarlar hesabın oturum açık olduğu tüm cihazlarda geçerlidir. '
            'Bu cihazdaki bildirimleri Ayarlar > Bildirimler ile kapatabilirsiniz.',
            style: TextStyle(color: colors.secondaryText),
          ),
          const SizedBox(height: 16),
          for (final account in _accounts) _accountCard(account),
        ],
      ),
    );
  }

  Widget _accountCard(MailAccount account) {
    final colors = AppTheme.colors(context);
    final settings = _settings[account.id];
    final error = _errors[account.id];
    final saving = _saving.contains(account.id);
    return Card(
      key: Key('notification-account-${account.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(
                account.email,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              trailing: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            if (_loading.contains(account.id))
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              )
            else if (error != null)
              ListTile(
                title: Text(friendlyErrorMessage(error)),
                trailing: TextButton(
                  key: Key('notification-retry-${account.id}'),
                  onPressed: () => _load(account.id),
                  child: const Text('Tekrar dene'),
                ),
              )
            else if (settings != null) ...[
              SwitchListTile(
                key: Key('notification-enabled-${account.id}'),
                title: const Text('Bildirimler'),
                subtitle: const Text(
                  'Yeni e-posta ve ertelenen e-posta bildirimleri',
                ),
                value: settings.enabled,
                onChanged: saving
                    ? null
                    : (value) =>
                          _save(account.id, settings.copyWith(enabled: value)),
              ),
              SwitchListTile(
                key: Key('notification-inbox-only-${account.id}'),
                title: const Text('Yalnızca Gelen Kutusu'),
                subtitle: const Text(
                  'Kapalıyken Gönderilmiş, Taslaklar, Çöp ve Spam dışındaki '
                  'senkronize klasörler de bildirilir.',
                ),
                value: settings.inboxOnly,
                onChanged: saving || !settings.enabled
                    ? null
                    : (value) => _save(
                        account.id,
                        settings.copyWith(inboxOnly: value),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Kilit ekranı gizliliği',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final privacy in NotificationPrivacy.values)
                ListTile(
                  key: Key(
                    'notification-privacy-${account.id}-${privacy.backendValue}',
                  ),
                  enabled: !saving && settings.enabled,
                  title: Text(privacy.label),
                  subtitle: Text(privacy.description),
                  trailing: settings.privacy == privacy
                      ? Icon(
                          LucideIcons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () =>
                      _save(account.id, settings.copyWith(privacy: privacy)),
                ),
              if (!settings.previewsAllowedByServer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Sunucu önizlemeleri kapattığı için bildirimler Gizli '
                    'olarak gönderilir.',
                    style: TextStyle(color: colors.secondaryText),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
