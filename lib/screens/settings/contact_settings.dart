import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../utils/error_messages.dart';
import '../../models/manual_contact.dart';
import '../../theme/app_theme.dart';
import '../../l10n/l10n.dart';

class ContactsSection extends StatelessWidget {
  const ContactsSection({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    final contacts = repo.getManualContactsForAccount(accountId);
    return Column(
      children: [
        if (contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10nNow.noContactsAddedYet,
              style: TextStyle(color: AppTheme.colors(context).secondaryText),
            ),
          ),
        for (final contact in contacts)
          ListTile(
            dense: true,
            leading: const CircleAvatar(
              radius: 14,
              child: Icon(LucideIcons.user, size: 14),
            ),
            title: Text(contact.label),
            subtitle: contact.displayName == null ? null : Text(contact.email),
            trailing: IconButton(
              tooltip: l10nNow.edit,
              icon: const Icon(LucideIcons.pencil, size: 18),
              onPressed: () => _showContactEditor(context, contact: contact),
            ),
          ),
        TextButton.icon(
          onPressed: () => _showContactEditor(context),
          icon: const Icon(LucideIcons.plus, size: 18),
          label: Text(l10nNow.newContact),
        ),
      ],
    );
  }

  Future<void> _showContactEditor(
    BuildContext context, {
    ManualContact? contact,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          _ContactEditorDialog(accountId: accountId, contact: contact),
    );
  }
}

/// Compact contact editor. With [contact] set it edits/deletes an existing
/// one (id preserved); without it, it creates a new one.
class _ContactEditorDialog extends StatefulWidget {
  const _ContactEditorDialog({required this.accountId, this.contact});

  final String accountId;
  final ManualContact? contact;

  @override
  State<_ContactEditorDialog> createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<_ContactEditorDialog> {
  late final TextEditingController _emailController;
  late final TextEditingController _nameController;
  String? _error;
  bool _submitting = false;

  bool get _isEdit => widget.contact != null;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.contact?.email ?? '');
    _nameController = TextEditingController(
      text: widget.contact?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = AppConfig.mailRepository;
    try {
      if (_isEdit) {
        await repo.updateManualContact(
          id: widget.contact!.id,
          email: email,
          displayName: name.isEmpty ? null : name,
        );
      } else {
        await repo.addManualContact(
          email: email,
          displayName: name.isEmpty ? null : name,
          accountId: widget.accountId,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message?.toString();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10nNow.deleteContact),
        content: Text(l10nNow.willBeRemovedFromThe(widget.contact!.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10nNow.cancel2),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10nNow.yesDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await AppConfig.mailRepository.deleteManualContact(widget.contact!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? l10nNow.editContact : l10nNow.newContact),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _emailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l10nNow.email,
              errorText: _error,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10nNow.nameOptional),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10nNow.cancel2),
        ),
        if (_isEdit)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.colors(context).destructive,
            ),
            child: Text(l10nNow.delete),
          ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEdit ? l10nNow.save : l10nNow.add),
        ),
      ],
    );
  }
}
