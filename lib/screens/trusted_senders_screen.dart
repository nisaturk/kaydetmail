import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/trusted_sender.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

class TrustedSendersScreen extends StatefulWidget {
  const TrustedSendersScreen({super.key});

  @override
  State<TrustedSendersScreen> createState() => _TrustedSendersScreenState();
}

class _TrustedSendersScreenState extends State<TrustedSendersScreen> {
  MailRepository get _repo => AppConfig.mailRepository;
  String? _accountId;
  List<TrustedSender> _items = const [];
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
      final items = await _repo.listTrustedSenders(accountId);
      if (!mounted || accountId != _accountId) return;
      setState(() {
        _items = items;
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

  Future<void> _remove(TrustedSender item) async {
    final accountId = _accountId;
    if (accountId == null) return;
    try {
      await _repo.removeTrustedSender(accountId, item.id);
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
      title: const Text('Güvenilir Göndericiler'),
      actions: [
        if (_repo.accounts.length > 1)
          PopupMenuButton<String>(
            key: const Key('trusted-senders-account-menu'),
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
        : _items.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Uzak görselleri otomatik yüklenen gönderici yok.\n'
                'Bir e-postada "Bu göndericiden her zaman" seçeneğiyle '
                'ekleyebilirsiniz.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.separated(
            itemCount: _items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _items[index];
              final domain = item.kind == TrustedSenderKind.domain;
              return ListTile(
                key: ValueKey('trusted-${item.id}'),
                leading: Icon(domain ? LucideIcons.globe : LucideIcons.user),
                title: Text(item.value),
                subtitle: Text(domain ? 'Alan adı' : 'Gönderici'),
                trailing: IconButton(
                  tooltip: 'Kaldır',
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: () => _remove(item),
                ),
              );
            },
          ),
  );
}
