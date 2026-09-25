import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/account_sync_scope.dart';
import '../models/mail_account.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';

class SyncScopeScreen extends StatefulWidget {
  const SyncScopeScreen({super.key, required this.account});

  final MailAccount account;

  @override
  State<SyncScopeScreen> createState() => _SyncScopeScreenState();
}

class _SyncScopeScreenState extends State<SyncScopeScreen> {
  AccountSyncScope? _current;
  FolderSyncScope _scope = FolderSyncScope.inboxAndSent;
  final Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;
  Object? _error;

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
      final current = await AppConfig.mailRepository.getSyncScope(
        widget.account.id,
      );
      if (!mounted) return;
      setState(() {
        _current = current;
        _scope = current.scope;
        _selected
          ..clear()
          ..addAll(current.folders.where((f) => f.synced).map((f) => f.id));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving ||
        (_scope == FolderSyncScope.selectedFolders && _selected.isEmpty)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await AppConfig.mailRepository.updateSyncScope(
        widget.account.id,
        _scope,
        folderIds: _scope == FolderSyncScope.selectedFolders
            ? _selected.toList()
            : null,
      );
      if (!mounted) return;
      setState(() {
        _current = updated;
        _scope = updated.scope;
        _selected
          ..clear()
          ..addAll(updated.folders.where((f) => f.synced).map((f) => f.id));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senkronizasyon kapsamı kaydedildi.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final current = _current;
    return Scaffold(
      appBar: AppBar(title: const Text('Senkronizasyon kapsamı')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(friendlyErrorMessage(_error!)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            )
          : current == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.account.email,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Arka planda güncellenecek klasörleri seçin. Diğer klasörler açıldığında yine yenilenir.',
                  style: TextStyle(color: colors.secondaryText),
                ),
                const SizedBox(height: 20),
                for (final option in FolderSyncScope.values)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      key: Key('sync-scope-${option.backendValue}'),
                      title: Text(option.label),
                      trailing: _scope == option
                          ? Icon(
                              LucideIcons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: _saving
                          ? null
                          : () => setState(() => _scope = option),
                    ),
                  ),
                if (_scope == FolderSyncScope.selectedFolders) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Klasörler',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final folder in current.folders)
                    CheckboxListTile(
                      key: Key('sync-folder-${folder.id}'),
                      title: Text(folder.displayName),
                      subtitle: folder.type == 'Custom'
                          ? Text(folder.name)
                          : null,
                      value: _selected.contains(folder.id),
                      onChanged: _saving
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(folder.id);
                              } else {
                                _selected.remove(folder.id);
                              }
                            }),
                    ),
                  if (_selected.isEmpty)
                    Text(
                      'En az bir klasör seçin.',
                      style: TextStyle(color: colors.destructive),
                    ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('save-sync-scope'),
                  onPressed:
                      _saving ||
                          (_scope == FolderSyncScope.selectedFolders &&
                              _selected.isEmpty)
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Arka planda senkronize edilen klasörler: ${current.folders.where((f) => f.synced).map((f) => f.displayName).join(', ')}',
                  style: TextStyle(color: colors.secondaryText),
                ),
              ],
            ),
    );
  }
}
