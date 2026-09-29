import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../models/email.dart';
import '../../state/pending_send_queue.dart';
import '../../theme/app_theme.dart';
import '../../utils/compose_signature.dart';
import '../../utils/error_messages.dart';
import '../../l10n/l10n.dart';

class QuickReply extends StatefulWidget {
  const QuickReply({super.key, required this.email, required this.from});

  final Email email;
  final String? from;

  @override
  State<QuickReply> createState() => _QuickReplyState();
}

class _QuickReplyState extends State<QuickReply> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final repo = AppConfig.mailRepository;
    final email = widget.email;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      // Prefill ve kimlik paralel çekilir; kimlik alınamazsa varsayılanla
      // devam edilir.
      final prefillFuture = repo.getComposePrefill(email.id, 'reply');
      final identityFuture = repo
          .listIdentities(email.accountId)
          .then((items) => items.where((item) => item.isDefault).firstOrNull)
          .catchError((_) => null);
      final prefill = await prefillFuture;
      final identity = await identityFuture;
      final signature = await resolveComposeSignature(
        repo,
        accountId: email.accountId,
        mode: ComposeSignatureMode.reply,
        identity: identity,
      );
      final queue = PendingSendQueue.instance;
      final pending = PendingSend(
        id: queue.nextId(),
        to: prefill.to,
        cc: prefill.cc,
        subject: prefill.suggestedSubject,
        body: signature.trim().isEmpty ? text : '$text\n\n--\n$signature',
        from: widget.from,
        fromAccountId: email.accountId,
        threadId: email.threadId,
        inReplyToId: email.id,
        identityId: identity?.id,
      );
      await queue.enqueue(pending, messenger: messenger);
      final queued = queue.isPending(pending.id);
      // Yanıtlandı işareti ağ çağrısı yapar; toast'ı bekletmesin.
      unawaited(repo.markAsReplied([email.id]).catchError((Object _) {}));
      if (!mounted) return;
      if (queued) _controller.clear();
      setState(() => _sending = false);
      final undoWindow = PendingSendQueue.undoWindow;
      messenger.showSnackBar(
        SnackBar(
          content: Text(queued ? l10nNow.sendingReply : l10nNow.replySent),
          // Aksiyonlu SnackBar varsayılan olarak kalıcıdır; süre dolunca
          // kapanması için açıkça kapatılır.
          persist: false,
          duration: queued && undoWindow > Duration.zero
              ? undoWindow
              : const Duration(seconds: 3),
          action: queued && undoWindow > Duration.zero
              ? SnackBarAction(
                  label: l10nNow.undo,
                  onPressed: () {
                    if (queue.cancel(pending.id) && mounted) {
                      _controller.text = text;
                    }
                  },
                )
              : null,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10nNow.couldntSendTheReply(friendlyErrorMessage(error)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      key: const Key('quick-reply'),
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: colors.border.withValues(alpha: 0.6),
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('quick-reply-field'),
              controller: _controller,
              enabled: !_sending,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10nNow.writeAQuickReply,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          IconButton(
            key: const Key('quick-reply-send'),
            tooltip: l10nNow.sendReply,
            onPressed: _sending || _controller.text.trim().isEmpty
                ? null
                : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.send),
          ),
        ],
      ),
    );
  }
}
