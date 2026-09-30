part of '../mail_detail_screen.dart';

mixin _MenuMixin
    on _MailDetailStateBase, _ThreadLoadMixin, _MailActionsMixin, _ReplyMixin {
  Future<void> _handleMenu(String action) async {
    if (action == 'reply') {
      await _reply();
    } else if (action == 'forward') {
      await _forward();
    } else if (action == 'reply_all') {
      await _replyAll();
    } else if (action == 'read') {
      _watchBackgroundMutation(_repo.markAsRead([widget.emailId]));
    } else if (action == 'unread') {
      _watchBackgroundMutation(_repo.markAsUnread([widget.emailId]));
    } else if (action == 'pin') {
      await _togglePin();
    } else if (action == 'star') {
      await _toggleStar();
    } else if (action == 'snooze') {
      await _toggleSnooze();
    } else if (action == 'label') {
      await showLabelPicker(context, emailIds: [widget.emailId]);
    } else if (action == 'unlabel') {
      _watchBackgroundMutation(removeAllLabels(_repo, [widget.emailId]));
    } else if (action == 'delete_forever') {
      await _deleteForever();
    } else if (action == 'move') {
      await _moveMail();
    } else if (action == 'print') {
      await _printMail();
    } else if (action == 'share_pdf') {
      await _sharePdf();
    } else if (action == 'unsubscribe') {
      await _unsubscribe();
    } else if (action == 'all_headers' || action == 'raw_mime') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MailInspectionScreen(
            mailId: widget.emailId,
            mode: action == 'all_headers'
                ? MailInspectionMode.headers
                : MailInspectionMode.source,
            repository: _repo,
          ),
        ),
      );
    }
  }

  /// Fires the header-driven unsubscribe action for the open mail. A
  /// one-click (RFC 8058) request asks for confirmation first — it's a
  /// real POST to the sender's server and, unlike opening a browser tab,
  /// can't be walked back by just closing the page.

  Future<void> _unsubscribe() async {
    final email = _email;
    if (email == null) return;
    final info = parseUnsubscribeHeaders(email.headers);
    if (info == null || !info.hasAction) return;

    if (info.oneClick) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10nNow.unsubscribe2),
          content: Text(l10nNow.aRequestWillBeSent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10nNow.cancel2),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10nNow.unsubscribe),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final success = await performUnsubscribe(info);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (info.oneClick
                      ? l10nNow.unsubscribed
                      : l10nNow.unsubscribeStarted)
                : l10nNow.unsubscribingFailed,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10nNow.actionFailed(friendlyErrorMessage(error))),
        ),
      );
    }
  }

  /// Opens the OS print dialog for the open mail's PDF rendering.
  Future<void> _printMail() async {
    final email = _email;
    if (email == null) return;
    try {
      await printMailPdf(email);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10nNow.printingFailed(friendlyErrorMessage(error))),
        ),
      );
    }
  }

  /// Opens the OS share sheet with the open mail's PDF rendering.
  Future<void> _sharePdf() async {
    final email = _email;
    if (email == null) return;
    try {
      await shareMailPdf(email);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10nNow.sharingThePdfFailed(friendlyErrorMessage(error)),
          ),
        ),
      );
    }
  }
}
