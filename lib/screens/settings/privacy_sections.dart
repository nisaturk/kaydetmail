import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../models/mail_session.dart';
import '../../state/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_format.dart';
import '../../utils/error_messages.dart';

class CleanTrackingQueriesSection extends StatelessWidget {
  const CleanTrackingQueriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return SwitchListTile(
      key: const Key('clean-tracking-queries-toggle'),
      dense: true,
      title: const Text('Bağlantı takip parametrelerini temizle'),
      subtitle: const Text(
        'E-postalardaki bağlantıları açmadan önce bilinen reklam ve kampanya '
        'takip parametrelerini kaldırır.',
      ),
      value: settings.cleanTrackingQueries,
      onChanged: (value) => settings.cleanTrackingQueries = value,
    );
  }
}

/// Local biometric/device-credential app lock toggle — see
/// `BiometricLockGate` for the actual enforcement.
class BiometricLockSection extends StatelessWidget {
  const BiometricLockSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          dense: true,
          title: const Text('Uygulama Kilidi'),
          subtitle: const Text(
            'Uygulamayı açtığınızda ya da seçilen süreden uzun arka planda '
            'kaldıktan sonra parmak izi/Face ID veya cihaz şifresi ister.',
          ),
          value: settings.biometricLockEnabled,
          onChanged: (v) => settings.biometricLockEnabled = v,
        ),
        if (settings.biometricLockEnabled) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Arka plandan dönünce kilitle',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          for (final timeout in BiometricLockTimeout.values)
            ListTile(
              dense: true,
              key: ValueKey('biometric-timeout-${timeout.name}'),
              title: Text(timeout.label),
              trailing: timeout == settings.biometricLockTimeout
                  ? const Icon(LucideIcons.check, size: 20)
                  : null,
              onTap: () => settings.biometricLockTimeout = timeout,
            ),
        ],
      ],
    );
  }
}

/// Privacy-screen toggle (`FLAG_SECURE` on Android, app-switcher cover on
/// iOS) — see `ScreenProtectionService`. Hidden where there is no native
/// side (web/desktop).
class ScreenProtectionSection extends StatelessWidget {
  const ScreenProtectionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    final settings = AppSettingsController.instance;
    return SwitchListTile(
      key: const ValueKey('screen-protection-switch'),
      dense: true,
      title: const Text('Ekran Koruması'),
      subtitle: Text(
        platform == TargetPlatform.iOS
            ? 'Uygulama geçiş ekranında posta içeriğini gizler.'
            : 'Ekran görüntüsü ve ekran kaydını engeller, son kullanılan '
                  'uygulamalar listesinde içeriği gizler.',
      ),
      value: settings.screenProtectionEnabled,
      onChanged: (value) => settings.screenProtectionEnabled = value,
    );
  }
}

/// Lists every device signed into the account and lets the user close any
/// of them remotely. Fetched on demand (not part of the repository's
/// change-notifier state), so it keeps its own loading/error state.
class SessionsSection extends StatefulWidget {
  const SessionsSection({super.key, required this.accountId});

  final String accountId;

  @override
  State<SessionsSection> createState() => _SessionsSectionState();
}

class _SessionsSectionState extends State<SessionsSection> {
  List<MailSession>? _sessions;
  String? _error;
  String? _revokingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final sessions = await AppConfig.mailRepository.getSessions(
        accountId: widget.accountId,
      );
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = 'Cihazlar yüklenemedi: ${friendlyErrorMessage(e)}',
      );
    }
  }

  Future<void> _revoke(MailSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oturumu kapat?'),
        content: Text(
          session.isCurrentDevice
              ? 'Bu cihazdaki oturum kapatılacak ve bu hesaptan çıkış yapılacak.'
              : 'Bu cihaz artık bu hesaba erişemeyecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revokingId = session.id);
    try {
      await AppConfig.mailRepository.revokeSession(
        session.id,
        accountId: widget.accountId,
      );
      if (session.isCurrentDevice) {
        if (!mounted) return;
        await _signOutAfterRevoke();
        return;
      }
      if (!mounted) return;
      setState(() {
        _sessions = _sessions?.where((s) => s.id != session.id).toList();
        _revokingId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _revokingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Oturum kapatılamadı: ${friendlyErrorMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _signOutAfterRevoke() async {
    // Only this account loses its session; other connected accounts stay.
    await AppConfig.mailRepository.signOutAccount(widget.accountId);
    // The root auth coordinator observes a full logout (last account) and
    // clears every authenticated route before showing Login.
    if (mounted && AppConfig.mailRepository.isLoggedIn) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    if (_error != null) {
      // Narrow viewport + large text: a ListTile trailing leaves no room
      // for the message, so stack the retry button below it instead.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  size: 20,
                  color: AppTheme.colors(context).secondaryText,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_error!)),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _load,
                child: const Text('Tekrar dene'),
              ),
            ),
          ],
        ),
      );
    }
    if (sessions == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Bağlı cihaz yok.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.colors(context).secondaryText,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final session in sessions)
          ListTile(
            dense: true,
            leading: Icon(
              LucideIcons.smartphone,
              size: 20,
              color: AppTheme.colors(context).secondaryText,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    session.deviceIdentifier,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (session.isCurrentDevice) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.colors(context).unreadBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppTheme.colors(context).border,
                      ),
                    ),
                    child: Text(
                      'Bu cihaz',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.colors(context).secondaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              'Son kullanım: ${formatMailTime(session.lastUsedAt)}',
            ),
            trailing: _revokingId == session.id
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: () => _revoke(session),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.colors(context).destructive,
                    ),
                    child: const Text('Kapat'),
                  ),
          ),
      ],
    );
  }
}
