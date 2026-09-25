import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_custom_folder.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import 'custom_folder_mail_screen.dart';

String customFolderErrorMessage(Object error) {
  if (error is ApiException) {
    return switch (error.code) {
      'mail_folder_exists' => 'Bu adda bir klasör zaten var.',
      'mail_folder_not_empty' =>
        'Klasör boş değil. Önce içindeki postaları taşıyın veya silin.',
      'mail_folder_has_children' => 'Önce alt klasörleri silin.',
      'mail_folder_protected' => 'Bu klasör değiştirilemez.',
      'invalid_folder_name' => 'Klasör adı geçersiz.',
      'mail_folder_rejected' => 'Posta sunucusu bu klasör adını kabul etmedi.',
      _ => friendlyErrorMessage(error),
    };
  }
  return friendlyErrorMessage(error);
}

String? validateCustomFolderName(String name, {String? delimiter}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Klasör adı boş olamaz.';
  if (trimmed.length > 200 ||
      trimmed.runes.any((character) => character < 32 || character == 127)) {
    return 'Klasör adı geçersiz.';
  }
  if (delimiter != null &&
      delimiter.isNotEmpty &&
      trimmed.contains(delimiter)) {
    return 'Klasör adı "$delimiter" karakterini içeremez.';
  }
  return null;
}

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
  bool _busy = false;
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

  Future<String?> _chooseAccount() async {
    if (_repo.activeAccountId != null || _repo.accounts.length <= 1) {
      return _repo.activeAccountId ?? _repo.accounts.firstOrNull?.id;
    }
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Hesap seçin'),
        children: [
          for (final account in _repo.accounts)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(account.id),
              child: Text(account.email),
            ),
        ],
      ),
    );
  }

  Future<String?> _askName({
    required String title,
    required String initial,
    required String? delimiter,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _FolderNameDialog(title: title, initial: initial, delimiter: delimiter),
  );

  Future<void> _create({String? parentFolderId}) async {
    final accountId = await _chooseAccount();
    if (accountId == null || !mounted) return;
    final folders = _repo.getCustomFolders(accountId: accountId);
    final parent = parentFolderId == null
        ? null
        : folders
              .where((folder) => folder.folderId == parentFolderId)
              .firstOrNull;
    final delimiter = parent?.delimiter ?? folders.firstOrNull?.delimiter;
    final name = await _askName(
      title: parent == null ? 'Yeni klasör' : 'Alt klasör oluştur',
      initial: '',
      delimiter: delimiter,
    );
    if (name == null || !mounted) return;
    await _perform(
      () => _repo.createCustomFolder(
        accountId: accountId,
        name: name,
        parentFolderId: parentFolderId,
      ),
      success: 'Klasör oluşturuldu.',
    );
  }

  Future<void> _rename(MailCustomFolder folder) async {
    final name = await _askName(
      title: 'Yeniden adlandır',
      initial: folder.name,
      delimiter: folder.delimiter,
    );
    if (name == null || !mounted) return;
    await _perform(
      () => _repo.renameCustomFolder(
        accountId: folder.accountId,
        folderId: folder.folderId,
        name: name,
      ),
      success: 'Klasör yeniden adlandırıldı.',
    );
  }

  Future<void> _delete(MailCustomFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Klasör silinsin mi?'),
        content: Text('"${folder.name}" klasörü kalıcı olarak silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(
      () => _repo.deleteCustomFolder(
        accountId: folder.accountId,
        folderId: folder.folderId,
      ),
      success: 'Klasör silindi.',
    );
  }

  Future<void> _perform(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(customFolderErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final folders = _repo.getCustomFolders();
    final showAccounts =
        _repo.activeAccountId == null && _repo.accounts.length > 1;
    final accountNames = {
      for (final account in _repo.accounts) account.id: account.email,
    };
    final groups = <String, List<MailCustomFolder>>{};
    for (final folder in folders) {
      groups.putIfAbsent(folder.accountId, () => []).add(folder);
    }
    final accountIds = showAccounts
        ? _repo.accounts
              .map((account) => account.id)
              .where(groups.containsKey)
              .toList()
        : groups.keys.toList();

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _ErrorState(message: _error!, onRetry: _load);
    } else if (folders.isEmpty) {
      body = _EmptyState(onRefresh: _load);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (final accountId in accountIds) ...[
              if (showAccounts)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(
                    accountNames[accountId] ?? '',
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              for (final row in flattenCustomFolderTree(groups[accountId]!))
                _folderRow(row.folder, row.depth),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diğer Klasörler'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _create(),
        icon: const Icon(LucideIcons.folderPlus),
        label: const Text('Yeni klasör'),
      ),
    );
  }

  Widget _folderRow(MailCustomFolder folder, int depth) {
    final colors = AppTheme.colors(context);
    return ListTile(
      contentPadding: EdgeInsets.only(left: 16.0 + 24.0 * depth, right: 8),
      leading: Icon(LucideIcons.folder, color: colors.secondaryText),
      title: Text(folder.name),
      subtitle: folder.unreadCount != null && folder.unreadCount! > 0
          ? Text('${folder.unreadCount} okunmamış')
          : null,
      trailing: PopupMenuButton<String>(
        enabled: !_busy,
        onSelected: (action) {
          switch (action) {
            case 'child':
              _create(parentFolderId: folder.folderId);
            case 'rename':
              _rename(folder);
            case 'delete':
              _delete(folder);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'child', child: Text('Alt klasör oluştur')),
          PopupMenuItem(value: 'rename', child: Text('Yeniden adlandır')),
          PopupMenuItem(value: 'delete', child: Text('Sil')),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomFolderMailScreen(
            accountId: folder.accountId,
            folderId: folder.folderId,
            name: folder.name,
          ),
        ),
      ),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.initial,
    required this.delimiter,
  });

  final String title;
  final String initial;
  final String? delimiter;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validateCustomFolderName(
      _controller.text,
      delimiter: widget.delimiter,
    );
    setState(() => _error = error);
    if (error == null) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: 'Klasör adı', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Kaydet')),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 240, child: Center(child: Text('Özel klasör yok'))),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
      ],
    ),
  );
}
