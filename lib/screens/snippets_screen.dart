import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_snippet.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  MailRepository get _repo => AppConfig.mailRepository;
  String? _accountId;
  List<MailSnippet> _snippets = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_repo.accounts.isNotEmpty) {
      _accountId = _repo.activeAccountId ?? _repo.accounts.first.id;
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    final accountId = _accountId;
    if (accountId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snippets = await _repo.listSnippets(accountId, refresh: true);
      if (!mounted || accountId != _accountId) return;
      setState(() {
        _snippets = snippets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || accountId != _accountId) return;
      setState(() {
        _error = friendlyErrorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _edit([MailSnippet? snippet]) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SnippetEditor(
        accountId: accountId,
        repository: _repo,
        snippet: snippet,
      ),
    );
    if (saved == true && mounted && accountId == _accountId) await _load();
  }

  Future<void> _delete(MailSnippet snippet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hazır metni sil?'),
        content: Text('“${snippet.title ?? snippet.text}” kalıcı silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _accountId == null) return;
    try {
      await _repo.deleteSnippet(_accountId!, snippet.id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Hazır Metinler'),
      actions: [
        if (_repo.accounts.length > 1)
          PopupMenuButton<String>(
            key: const Key('snippets-account-menu'),
            tooltip: 'Hesap seç',
            icon: const Icon(LucideIcons.chevronDown),
            onSelected: (id) {
              if (id == _accountId) return;
              setState(() => _accountId = id);
              _load();
            },
            itemBuilder: (_) => [
              for (final account in _repo.accounts)
                PopupMenuItem(value: account.id, child: Text(account.label)),
            ],
          ),
      ],
    ),
    body: _repo.accounts.isEmpty
        ? const Center(child: Text('Bağlı hesap bulunamadı.'))
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
                TextButton(onPressed: _load, child: const Text('Tekrar dene')),
              ],
            ),
          )
        : _snippets.isEmpty
        ? const Center(child: Text('Henüz hazır metin yok'))
        : ListView.separated(
            itemCount: _snippets.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final snippet = _snippets[index];
              return ListTile(
                key: ValueKey('snippet-${snippet.id}'),
                leading: const Icon(LucideIcons.quote),
                title: Text(
                  (snippet.title?.isNotEmpty == true
                      ? snippet.title!
                      : snippet.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: snippet.title?.isNotEmpty == true
                    ? Text(snippet.text, maxLines: 1)
                    : null,
                onTap: () => _edit(snippet),
                trailing: IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: () => _delete(snippet),
                ),
              );
            },
          ),
    floatingActionButton: _loading || _error != null || _accountId == null
        ? null
        : FloatingActionButton(
            key: const Key('add-snippet-fab'),
            tooltip: 'Yeni hazır metin',
            onPressed: () => _edit(),
            child: const Icon(LucideIcons.plus),
          ),
  );
}

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({
    required this.accountId,
    required this.repository,
    this.snippet,
  });

  final String accountId;
  final MailRepository repository;
  final MailSnippet? snippet;

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.snippet?.title ?? '');
    _text = TextEditingController(text: widget.snippet?.text ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final text = _text.text.trim();
    if (title.length > 100) {
      setState(() => _error = 'Başlık en fazla 100 karakter olmalı.');
      return;
    }
    if (text.isEmpty || text.length > 2000) {
      setState(() => _error = 'Metin 1-2000 karakter olmalı.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now().toUtc();
    final snippet = MailSnippet(
      id: widget.snippet?.id ?? '',
      accountId: widget.accountId,
      title: title.isEmpty ? null : title,
      text: text,
      sortOrder: widget.snippet?.sortOrder ?? 0,
      createdAt: widget.snippet?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      if (widget.snippet == null) {
        await widget.repository.createSnippet(widget.accountId, snippet);
      } else {
        await widget.repository.updateSnippet(widget.accountId, snippet);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 20,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.snippet == null ? 'Yeni hazır metin' : 'Hazır metni düzenle',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('snippet-title'),
            controller: _title,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Başlık (isteğe bağlı)',
            ),
          ),
          TextField(
            key: const Key('snippet-text'),
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Metin'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('save-snippet'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
}
