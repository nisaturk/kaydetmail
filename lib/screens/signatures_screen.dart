import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_signature.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

class SignaturesScreen extends StatefulWidget {
  const SignaturesScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<SignaturesScreen> createState() => _SignaturesScreenState();
}

class _SignaturesScreenState extends State<SignaturesScreen> {
  MailRepository get _repo => AppConfig.mailRepository;
  String? _accountId;
  List<MailSignature> _signatures = const [];
  SignatureDefaults _defaults = const SignatureDefaults();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accountId;
    _load();
  }

  Future<void> _load() async {
    final accountId = _accountId;
    if (accountId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final signatures = await _repo.listSignatures(accountId, refresh: true);
      final defaults = await _repo.getSignatureDefaults(accountId);
      if (!mounted || accountId != _accountId) return;
      setState(() {
        _signatures = signatures;
        _defaults = defaults;
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

  Future<void> _editSignature([MailSignature? signature]) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SignatureEditor(
        accountId: accountId,
        repository: _repo,
        signature: signature,
      ),
    );
    if (saved == true && mounted && accountId == _accountId) await _load();
  }

  Future<void> _deleteSignature(MailSignature signature) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İmzayı sil?'),
        content: Text('“${signature.name}” imzası kalıcı olarak silinecek.'),
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
      await _repo.deleteSignature(_accountId!, signature.id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  Future<void> _pickDefault(String kind, String? current) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Yok'),
              trailing: current == null ? const Icon(LucideIcons.check) : null,
              onTap: () => Navigator.pop(context, _clearDefault),
            ),
            for (final signature in _signatures)
              ListTile(
                title: Text(signature.name),
                trailing: current == signature.id
                    ? const Icon(LucideIcons.check)
                    : null,
                onTap: () => Navigator.pop(context, signature.id),
              ),
          ],
        ),
      ),
    );
    if (!mounted || accountId != _accountId) return;
    if (picked == null) return;
    final nextId = identical(picked, _clearDefault) ? null : picked as String?;
    if (nextId == current) return;
    try {
      final next = switch (kind) {
        'reply' => SignatureDefaults(
          newMailSignatureId: _defaults.newMailSignatureId,
          replySignatureId: nextId,
          forwardSignatureId: _defaults.forwardSignatureId,
        ),
        'forward' => SignatureDefaults(
          newMailSignatureId: _defaults.newMailSignatureId,
          replySignatureId: _defaults.replySignatureId,
          forwardSignatureId: nextId,
        ),
        _ => SignatureDefaults(
          newMailSignatureId: nextId,
          replySignatureId: _defaults.replySignatureId,
          forwardSignatureId: _defaults.forwardSignatureId,
        ),
      };
      final updated = await _repo.updateSignatureDefaults(accountId, next);
      if (mounted) setState(() => _defaults = updated);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  String _defaultName(String? id) =>
      _signatures.where((item) => item.id == id).firstOrNull?.name ?? 'Yok';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('İmzalar')),
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
        : _SignatureList(
            signatures: _signatures,
            defaults: _defaults,
            defaultName: _defaultName,
            onDefaults: _pickDefault,
            onEdit: _editSignature,
            onDelete: _deleteSignature,
          ),
    floatingActionButton: _loading || _error != null || _accountId == null
        ? null
        : FloatingActionButton(
            key: const Key('add-signature-fab'),
            tooltip: 'Yeni imza',
            onPressed: _editSignature,
            child: const Icon(LucideIcons.plus),
          ),
  );
}

const _clearDefault = Object();

class _SignatureList extends StatelessWidget {
  const _SignatureList({
    required this.signatures,
    required this.defaults,
    required this.defaultName,
    required this.onDefaults,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MailSignature> signatures;
  final SignatureDefaults defaults;
  final String Function(String?) defaultName;
  final Future<void> Function(String, String?) onDefaults;
  final Future<void> Function(MailSignature?) onEdit;
  final Future<void> Function(MailSignature) onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      ListTile(
        title: const Text('Yeni e-posta'),
        subtitle: Text(defaultName(defaults.newMailSignatureId)),
        onTap: () => onDefaults('new', defaults.newMailSignatureId),
      ),
      ListTile(
        title: const Text('Yanıt'),
        subtitle: Text(defaultName(defaults.replySignatureId)),
        onTap: () => onDefaults('reply', defaults.replySignatureId),
      ),
      ListTile(
        title: const Text('İlet'),
        subtitle: Text(defaultName(defaults.forwardSignatureId)),
        onTap: () => onDefaults('forward', defaults.forwardSignatureId),
      ),
      const Divider(),
      if (signatures.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Henüz imza yok'),
        ),
      for (final signature in signatures)
        ListTile(
          key: ValueKey('signature-${signature.id}'),
          leading: const Icon(LucideIcons.penLine),
          title: Text(signature.name),
          subtitle: Text(
            signature.bodyText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onEdit(signature),
          trailing: IconButton(
            tooltip: 'Sil',
            icon: const Icon(LucideIcons.trash2),
            onPressed: () => onDelete(signature),
          ),
        ),
    ],
  );
}

class _SignatureEditor extends StatefulWidget {
  const _SignatureEditor({
    required this.accountId,
    required this.repository,
    this.signature,
  });

  final String accountId;
  final MailRepository repository;
  final MailSignature? signature;

  @override
  State<_SignatureEditor> createState() => _SignatureEditorState();
}

class _SignatureEditorState extends State<_SignatureEditor> {
  late final TextEditingController _name;
  late final TextEditingController _bodyText;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.signature?.name ?? '');
    _bodyText = TextEditingController(text: widget.signature?.bodyText ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _bodyText.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final bodyText = _bodyText.text.trim();
    if (name.isEmpty || name.length > 100) {
      setState(() => _error = 'İmza adı 1-100 karakter olmalı.');
      return;
    }
    if (bodyText.isEmpty) {
      setState(() => _error = 'İmza metni yazın.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now().toUtc();
    final signature = MailSignature(
      id: widget.signature?.id ?? '',
      accountId: widget.accountId,
      name: name,
      bodyText: bodyText,
      createdAt: widget.signature?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      if (widget.signature == null) {
        await widget.repository.createSignature(widget.accountId, signature);
      } else {
        await widget.repository.updateSignature(widget.accountId, signature);
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
            widget.signature == null ? 'Yeni imza' : 'İmzayı düzenle',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('signature-name'),
            controller: _name,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Ad'),
          ),
          TextField(
            key: const Key('signature-body-text'),
            controller: _bodyText,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'İmza metni'),
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
            key: const Key('save-signature'),
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
