import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_template.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  MailRepository get _repo => AppConfig.mailRepository;
  String? _accountId;
  List<MailTemplate> _templates = const [];
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
      final templates = await _repo.listTemplates(accountId, refresh: true);
      if (!mounted || accountId != _accountId) return;
      setState(() {
        _templates = templates;
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

  Future<void> _edit([MailTemplate? template]) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TemplateEditor(
        accountId: accountId,
        repository: _repo,
        template: template,
      ),
    );
    if (saved == true && mounted && accountId == _accountId) await _load();
  }

  Future<void> _delete(MailTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şablonu sil?'),
        content: Text('“${template.name}” şablonu kalıcı olarak silinecek.'),
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
      await _repo.deleteTemplate(_accountId!, template.id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Şablonlar'),
      actions: [
        if (_repo.accounts.length > 1)
          PopupMenuButton<String>(
            key: const Key('templates-account-menu'),
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
        : _templates.isEmpty
        ? const Center(child: Text('Henüz şablon yok'))
        : ListView.separated(
            itemCount: _templates.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final template = _templates[index];
              return ListTile(
                key: ValueKey('template-${template.id}'),
                leading: const Icon(LucideIcons.layoutTemplate),
                title: Text(template.name),
                subtitle: template.subject.isEmpty
                    ? const Text('Konu yok')
                    : Text(template.subject, maxLines: 1),
                onTap: () => _edit(template),
                trailing: IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: () => _delete(template),
                ),
              );
            },
          ),
    floatingActionButton: _loading || _error != null || _accountId == null
        ? null
        : FloatingActionButton(
            key: const Key('add-template-fab'),
            tooltip: 'Yeni şablon',
            onPressed: () => _edit(),
            child: const Icon(LucideIcons.plus),
          ),
  );
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({
    required this.accountId,
    required this.repository,
    this.template,
  });

  final String accountId;
  final MailRepository repository;
  final MailTemplate? template;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _name;
  late final TextEditingController _subject;
  late final TextEditingController _bodyText;
  late final TextEditingController _bodyHtml;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template?.name ?? '');
    _subject = TextEditingController(text: widget.template?.subject ?? '');
    _bodyText = TextEditingController(text: widget.template?.bodyText ?? '');
    _bodyHtml = TextEditingController(text: widget.template?.bodyHtml ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _bodyText.dispose();
    _bodyHtml.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final subject = _subject.text.trim();
    final bodyText = _bodyText.text.trim();
    final bodyHtml = _bodyHtml.text.trim();
    if (name.isEmpty || name.length > 100) {
      setState(() => _error = 'Şablon adı 1-100 karakter olmalı.');
      return;
    }
    if (subject.length > 500 || subject.contains('\n')) {
      setState(() => _error = 'Konu tek satır ve en fazla 500 karakter olmalı.');
      return;
    }
    if (bodyText.isEmpty && bodyHtml.isEmpty) {
      setState(() => _error = 'Metin veya HTML gövdesi yazın.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now().toUtc();
    final template = MailTemplate(
      id: widget.template?.id ?? '',
      accountId: widget.accountId,
      name: name,
      subject: subject,
      bodyText: bodyText.isEmpty ? null : bodyText,
      bodyHtml: bodyHtml.isEmpty ? null : bodyHtml,
      createdAt: widget.template?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      if (widget.template == null) {
        await widget.repository.createTemplate(widget.accountId, template);
      } else {
        await widget.repository.updateTemplate(widget.accountId, template);
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
            widget.template == null ? 'Yeni şablon' : 'Şablonu düzenle',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('template-name'),
            controller: _name,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Ad'),
          ),
          TextField(
            key: const Key('template-subject'),
            controller: _subject,
            maxLength: 500,
            maxLines: 1,
            decoration: const InputDecoration(labelText: 'Konu'),
          ),
          TextField(
            key: const Key('template-body-text'),
            controller: _bodyText,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Düz metin gövdesi'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('template-body-html'),
            controller: _bodyHtml,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'HTML gövdesi (isteğe bağlı)'),
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
            key: const Key('save-template'),
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
