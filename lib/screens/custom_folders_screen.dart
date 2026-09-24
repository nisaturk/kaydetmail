import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import 'custom_folder_mail_screen.dart';

/// Lists the server's non-standard IMAP folders for the active mailbox
/// scope — distinct from the fixed [MailFolder] set shown in the drawer and
/// from virtual groupings like starred/pinned.
class CustomFoldersScreen extends StatefulWidget {
  const CustomFoldersScreen({super.key});

  @override
  State<CustomFoldersScreen> createState() => _CustomFoldersScreenState();
}

class _CustomFoldersScreenState extends State<CustomFoldersScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.refreshCustomFolders();
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final showAccount =
        _repo.activeAccountId == null && _repo.accounts.length > 1;
    final accountEmail = showAccount
        ? {for (final a in _repo.accounts) a.id: a.email}
        : const <String, String>{};

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _ErrorState(message: _error!, onRetry: _load);
    } else {
      final folders = _repo.getCustomFolders();
      if (folders.isEmpty) {
        body = _EmptyState(onRefresh: _load);
      } else {
        body = RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: folders.length,
            separatorBuilder: (_, _) => const Divider(indent: 64, endIndent: 16),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                leading: Icon(LucideIcons.folder, color: colors.secondaryText),
                title: Text(folder.fullName),
                subtitle: accountEmail[folder.accountId] != null
                    ? Text(accountEmail[folder.accountId]!)
                    : null,
                trailing: folder.unreadCount != null && folder.unreadCount! > 0
                    ? _UnreadBadge(count: folder.unreadCount!)
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CustomFolderMailScreen(
                      accountId: folder.accountId,
                      folderId: folder.folderId,
                      name: folder.fullName,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Diğer Klasörler')),
      body: body,
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.folder, size: 40, color: colors.tertiaryText),
                    const SizedBox(height: 12),
                    Text(
                      'Özel klasör yok',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sunucudaki standart dışı klasörler burada görünür.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleAlert, size: 40, color: colors.warning),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}
