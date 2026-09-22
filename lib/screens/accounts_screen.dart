import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_account.dart';
import '../repositories/mail_repository.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/mail_avatar.dart';
import 'add_account_screen.dart';

/// Account management: shows every connected mailbox, the unified mailbox
/// entry (when more than one account exists) and the add-account row.
///
/// Tapping an account makes it the active mailbox and returns to the mail
/// list. Same minimalist drawer language: white, black, subtle dividers.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  MailRepository get _repo => AppConfig.mailRepository;

  Future<void> _select(BuildContext context, String? accountId) async {
    await _repo.setActiveAccount(accountId);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _remove(BuildContext context, MailAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabı kaldır'),
        content: Text(
          '${account.email} kaldırılacak ve bu hesaba ait e-postalar '
          'görünümden silinecek. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await _repo.removeAccount(account.id);
      await SessionStore.removeEmail(account.email);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  void _add(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AddAccountScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesaplar')),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final accounts = _repo.accounts;
          final activeId = _repo.activeAccountId;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (accounts.length > 1)
                _AccountRow(
                  key: const ValueKey('unified-row'),
                  title: 'Tüm Gelen Kutuları',
                  subtitle: 'Birleşik Gelen Kutusu',
                  icon: LucideIcons.inbox,
                  isActive: activeId == null,
                  onTap: () => _select(context, null),
                ),
              for (final account in accounts)
                _AccountRow(
                  key: ValueKey('account-${account.id}'),
                  title: account.email,
                  avatarIdentity: account.email,
                  isActive: account.id == activeId,
                  canRemove: accounts.length > 1,
                  onTap: () => _select(context, account.id),
                  onRemove: () => _remove(context, account),
                ),
              const Divider(),
              ListTile(
                key: const ValueKey('add-account-row'),
                leading: const Icon(
                  LucideIcons.plus,
                  size: 20,
                  color: AppTheme.secondaryText,
                ),
                title: const Text(
                  'Yeni hesap ekle',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                onTap: () => _add(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.isActive,
    required this.onTap,
    this.avatarIdentity,
    this.icon,
    this.canRemove = false,
    this.onRemove,
  });

  final String title;
  final String? subtitle;
  final bool isActive;
  final VoidCallback onTap;
  final String? avatarIdentity;
  final IconData? icon;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: isActive ? const Color(0xFFF3F4F6) : null,
      leading: avatarIdentity != null
          ? MailAvatar(identity: avatarIdentity!, displayName: title, size: 40)
          : Icon(icon, size: 20, color: AppTheme.secondaryText),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              isActive ? '$subtitle · Aktif' : subtitle!,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            const Icon(LucideIcons.check, size: 20, color: Colors.black),
          if (canRemove && onRemove != null)
            IconButton(
              tooltip: 'Hesabı kaldır',
              onPressed: onRemove,
              icon: const Icon(
                LucideIcons.trash2,
                size: 18,
                color: AppTheme.tertiaryText,
              ),
            ),
        ],
      ),
    );
  }
}
