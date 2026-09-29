import 'package:flutter/material.dart';

import '../repositories/mail_repository.dart';
import '../l10n/l10n.dart';

/// Collects IMAP/SMTP host+port when automatic server discovery fails
/// (`mail_discovery_failed`, `manualSetupAvailable: true`). Pops the entered
/// [MailServerSettings], or null if the user cancels.
class ManualMailSetupDialog extends StatefulWidget {
  const ManualMailSetupDialog({super.key, required this.email});

  final String email;

  static Future<MailServerSettings?> show(
    BuildContext context, {
    required String email,
  }) => showDialog<MailServerSettings>(
    context: context,
    builder: (_) => ManualMailSetupDialog(email: email),
  );

  @override
  State<ManualMailSetupDialog> createState() => _ManualMailSetupDialogState();
}

class _ManualMailSetupDialogState extends State<ManualMailSetupDialog> {
  late final TextEditingController _imapHost;
  late final TextEditingController _imapPort;
  late final TextEditingController _smtpHost;
  late final TextEditingController _smtpPort;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final domain = widget.email.trim().split('@').lastOrNull ?? '';
    // Automatic discovery already tried `imap.$domain` / `smtp.$domain` (and
    // SRV/autoconfig) before giving up — repeating that guess here just
    // reproduces the same dead end. `mail.$domain` is the more common
    // single-host fallback for domains without dedicated imap./smtp.
    // subdomains, so default to it for both fields; the user can still
    // override either one.
    _imapHost = TextEditingController(
      text: domain.isEmpty ? '' : 'mail.$domain',
    );
    _imapPort = TextEditingController(text: '993');
    _smtpHost = TextEditingController(
      text: domain.isEmpty ? '' : 'mail.$domain',
    );
    _smtpPort = TextEditingController(text: '587');
  }

  @override
  void dispose() {
    _imapHost.dispose();
    _imapPort.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      MailServerSettings(
        imapServer: _imapHost.text.trim(),
        imapPort: int.parse(_imapPort.text.trim()),
        smtpServer: _smtpHost.text.trim(),
        smtpPort: int.parse(_smtpPort.text.trim()),
      ),
    );
  }

  String? _requiredHost(String? value) =>
      (value == null || value.trim().isEmpty)
      ? l10nNow.serverAddressIsRequired
      : null;

  String? _validPort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port <= 0 || port > 65535) {
      return l10nNow.enterAValidPort;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10nNow.manualServerSettings),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10nNow.automaticServerDiscoveryFailedEnter,
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _imapHost,
                decoration: InputDecoration(labelText: l10nNow.imapServer),
                validator: _requiredHost,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _imapPort,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10nNow.imapPort),
                validator: _validPort,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _smtpHost,
                decoration: InputDecoration(labelText: l10nNow.smtpServer),
                validator: _requiredHost,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _smtpPort,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10nNow.smtpPort),
                validator: _validPort,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10nNow.cancel2),
        ),
        FilledButton(onPressed: _submit, child: Text(l10nNow.connect2)),
      ],
    );
  }
}
