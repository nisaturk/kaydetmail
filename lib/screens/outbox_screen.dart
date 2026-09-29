import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/outbox_store.dart';
import '../state/pending_send_queue.dart';
import '../utils/error_messages.dart';
import 'compose_screen.dart';
import '../l10n/l10n.dart';

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
    PendingSendQueue.instance.uploadProgress.addListener(_refreshForProgress);
    _refresh();
  }

  void _refreshForProgress() => _refresh();

  @override
  void dispose() {
    PendingSendQueue.instance.uploadProgress.removeListener(
      _refreshForProgress,
    );
    super.dispose();
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
          composeTitle: replacing ? l10nNow.editMessage : l10nNow.newMessage,
          replacesOutboxId: replacing ? send.id : null,
          initialFrom: send.from,
          initialTo: send.to.join(', '),
          initialCc: send.cc.join(', '),
          initialBcc: send.bcc.join(', '),
          initialSubject: send.subject,
          initialBody: send.body,
          initialBodyHtml: send.bodyHtml,
          initialAttachments: send.attachments,
          initialThreadId: send.threadId,
          inReplyToId: send.inReplyToId,
          editingDraftId: send.draftId,
          initialRequestReadReceipt: send.requestReadReceipt,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _manualResend(OutboxItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10nNow.createANewMessage),
        content: Text(l10nNow.checkSentFirstThisMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10nNow.cancel2),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10nNow.newMessage2),
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
        title: Text(l10nNow.deleteMessage),
        content: Text(
          item.status == OutboxStatus.uncertain
              ? l10nNow.theDeliveryResultIsUnknown
              : l10nNow.theLocalCopyOfThis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10nNow.cancel2),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10nNow.delete),
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
        title: Text(l10nNow.outbox),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(child: Text(l10nNow.noPendingMessages))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final send = item.send;
                final failed = item.status == OutboxStatus.failed;
                final uncertain = item.status == OutboxStatus.uncertain;
                final waitingForNetwork =
                    item.status == OutboxStatus.waitingForNetwork;
                final status = switch (item.status) {
                  OutboxStatus.pending => l10nNow.undoPeriod,
                  OutboxStatus.sending => l10nNow.sending,
                  OutboxStatus.waitingForNetwork =>
                    l10nNow.waitingForConnection,
                  OutboxStatus.failed => l10nNow.couldntSend,
                  OutboxStatus.uncertain => l10nNow.resultUnknown,
                };
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          send.subject.isEmpty
                              ? l10nNow.noSubject2
                              : send.subject,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(l10nNow.to3(send.to.join(', '))),
                        Text(status),
                        if (item.status == OutboxStatus.sending &&
                            send.attachments.isNotEmpty)
                          ValueListenableBuilder<Map<String, SendProgress>>(
                            valueListenable:
                                PendingSendQueue.instance.uploadProgress,
                            builder: (context, progressMap, _) {
                              final progress = progressMap[send.id];
                              if (progress == null) {
                                return const LinearProgressIndicator();
                              }
                              final percent = (progress.fraction * 100).round();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinearProgressIndicator(
                                    value: progress.fraction,
                                  ),
                                  Row(
                                    children: [
                                      Text('$percent%'),
                                      const Spacer(),
                                      if (progress.sent < progress.total)
                                        TextButton(
                                          onPressed: () {
                                            PendingSendQueue.instance
                                                .cancelUpload(send.id);
                                          },
                                          child: Text(l10nNow.cancel),
                                        ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        if (item.error != null) Text(item.error!),
                        if (waitingForNetwork)
                          Text(
                            l10nNow
                                .noInternetConnectionItWillBeSentAutomatically,
                          ),
                        if (uncertain)
                          Text(l10nNow.checkSentBeforeSendingAgain),
                        if (failed || uncertain || waitingForNetwork)
                          Row(
                            children: [
                              if (failed || waitingForNetwork) ...[
                                TextButton(
                                  onPressed: _busy ? null : () => _retry(item),
                                  child: Text(
                                    waitingForNetwork
                                        ? l10nNow.tryNow
                                        : l10nNow.tryAgain,
                                  ),
                                ),
                              ],
                              if (failed)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                            _openCompose(item, replacing: true),
                                  child: Text(l10nNow.edit),
                                ),
                              TextButton(
                                onPressed: _busy ? null : () => _discard(item),
                                child: Text(l10nNow.delete),
                              ),
                            ],
                          ),
                        if (uncertain)
                          TextButton(
                            onPressed: _busy ? null : () => _manualResend(item),
                            child: Text(l10nNow.recreateManually),
                          ),
                        if (uncertain)
                          TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  send.subject.isEmpty
                                      ? l10nNow.noSubject2
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
                                    child: Text(l10nNow.close),
                                  ),
                                ],
                              ),
                            ),
                            child: Text(l10nNow.viewContent),
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
