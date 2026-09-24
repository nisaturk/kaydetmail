import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/outbox_store.dart';
import '../state/pending_send_queue.dart';
import '../utils/error_messages.dart';
import 'compose_screen.dart';

class OutboxScreen extends StatefulWidget {
  const OutboxScreen({super.key});

  @override
  State<OutboxScreen> createState() => _OutboxScreenState();
}

class _OutboxScreenState extends State<OutboxScreen> {
  List<OutboxItem>? _items;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final accounts = AppConfig.mailRepository.accounts;
      final ids = accounts.map((account) => account.id).toSet();
      final emails = accounts
          .map((account) => account.email.toLowerCase())
          .toSet();
      final items = await PendingSendQueue.instance.items();
      if (!mounted) return;
      setState(() {
        _items = items
            .where(
              (item) =>
                  ids.contains(item.send.fromAccountId) ||
                  (item.send.fromAccountId == null &&
                      emails.contains(item.send.from?.toLowerCase())),
            )
            .toList();
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _retry(OutboxItem item) async {
    setState(() => _busy = true);
    try {
      await PendingSendQueue.instance.retry(item.send.id);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCompose(OutboxItem item, {required bool replacing}) async {
    final send = item.send;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          composeTitle: replacing ? 'Gönderiyi Düzenle' : 'Yeni Gönderi',
          replacesOutboxId: replacing ? send.id : null,
          initialFrom: send.from,
          initialTo: send.to.join(', '),
          initialCc: send.cc.join(', '),
          initialBcc: send.bcc.join(', '),
          initialSubject: send.subject,
          initialBody: send.body,
          initialAttachments: send.attachments,
          initialThreadId: send.threadId,
          inReplyToId: send.inReplyToId,
          editingDraftId: send.draftId,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _manualResend(OutboxItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni gönderi oluştur?'),
        content: const Text(
          'Önce Gönderilenler’i kontrol edin. Bu mesaj daha önce teslim edilmiş '
          'olabilir; yeniden göndermek alıcıya ikinci bir kopya ulaştırabilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yeni gönderi'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _openCompose(item, replacing: false);
    }
  }

  Future<void> _discard(OutboxItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi sil?'),
        content: Text(
          item.status == OutboxStatus.uncertain
              ? 'Gönderim sonucu bilinmiyor. Önce Gönderilenler’i kontrol edin. Yerel kopya silinsin mi?'
              : 'Bu gönderinin yerel kopyası kalıcı olarak silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await PendingSendQueue.instance.discard(item.send.id);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giden Kutusu'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('Bekleyen gönderi yok.'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final send = item.send;
                final failed = item.status == OutboxStatus.failed;
                final uncertain = item.status == OutboxStatus.uncertain;
                final status = switch (item.status) {
                  OutboxStatus.pending => 'Geri alma süresi',
                  OutboxStatus.sending => 'Gönderiliyor',
                  OutboxStatus.failed => 'Gönderilemedi',
                  OutboxStatus.uncertain => 'Sonuç belirsiz',
                };
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          send.subject.isEmpty ? '(Konu yok)' : send.subject,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('Kime: ${send.to.join(', ')}'),
                        Text(status),
                        if (item.error != null) Text(item.error!),
                        if (uncertain)
                          const Text(
                            'Tekrar göndermeden önce Gönderilenler’i kontrol edin.',
                          ),
                        if (failed || uncertain)
                          Row(
                            children: [
                              if (failed) ...[
                                TextButton(
                                  onPressed: _busy ? null : () => _retry(item),
                                  child: const Text('Tekrar dene'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                            _openCompose(item, replacing: true),
                                  child: const Text('Düzenle'),
                                ),
                              ],
                              TextButton(
                                onPressed: _busy ? null : () => _discard(item),
                                child: const Text('Sil'),
                              ),
                            ],
                          ),
                        if (uncertain)
                          TextButton(
                            onPressed: _busy ? null : () => _manualResend(item),
                            child: const Text('Elle yeniden oluştur'),
                          ),
                        if (uncertain)
                          TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  send.subject.isEmpty
                                      ? '(Konu yok)'
                                      : send.subject,
                                ),
                                content: SingleChildScrollView(
                                  child: Text(
                                    '${send.body}\n\n${send.attachments.map((a) => a.name).join(', ')}',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Kapat'),
                                  ),
                                ],
                              ),
                            ),
                            child: const Text('İçeriği görüntüle'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
