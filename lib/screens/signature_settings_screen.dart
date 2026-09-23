import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_account.dart';
import '../services/signature_store.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';

/// Per-account email signature, auto-inserted into new compose bodies (see
/// `_ComposeScreenState`'s signature handling in `compose_screen.dart`).
/// Purely client-side ([SignatureStore]) — no backend endpoint exists for
/// this, same as labels/rules.
class SignatureSettingsScreen extends StatefulWidget {
  const SignatureSettingsScreen({super.key});

  @override
  State<SignatureSettingsScreen> createState() =>
      _SignatureSettingsScreenState();
}

class _SignatureSettingsScreenState extends State<SignatureSettingsScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _saving = {};
  bool _loading = true;

  List<MailAccount> get _accounts => AppConfig.mailRepository.accounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = _accounts;
    final signatures = await Future.wait(
      accounts.map((account) => SignatureStore.load(account.email)),
    );
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < accounts.length; i++) {
        _controllers[accounts[i].email] = TextEditingController(
          text: signatures[i],
        );
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String accountEmail) async {
    final controller = _controllers[accountEmail];
    if (controller == null || _saving.contains(accountEmail)) return;
    setState(() => _saving.add(accountEmail));
    try {
      await SignatureStore.save(accountEmail, controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İmza kaydedildi.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İmza kaydedilemedi: ${friendlyErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(accountEmail));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İmza')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
          ? const Center(child: Text('Bağlı hesap bulunamadı.'))
          : ListView.separated(
              key: const Key('signature-list'),
              padding: const EdgeInsets.all(16),
              itemCount: _accounts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 24),
              itemBuilder: (context, index) =>
                  _AccountSignatureEditor(
                    account: _accounts[index],
                    controller: _controllers[_accounts[index].email]!,
                    saving: _saving.contains(_accounts[index].email),
                    onSave: () => _save(_accounts[index].email),
                  ),
            ),
    );
  }
}

class _AccountSignatureEditor extends StatelessWidget {
  const _AccountSignatureEditor({
    required this.account,
    required this.controller,
    required this.saving,
    required this.onSave,
  });

  final MailAccount account;
  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          account.email,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            key: ValueKey('signature-field-${account.email}'),
            controller: controller,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(fontSize: 14.5, color: colors.bodyText),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Örn. Saygılarımla,\nAd Soyad',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: ValueKey('signature-save-${account.email}'),
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.check, size: 16),
            label: const Text('Kaydet'),
          ),
        ),
      ],
    );
  }
}
