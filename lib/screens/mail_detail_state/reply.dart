part of '../mail_detail_screen.dart';

mixin _ReplyMixin on _MailDetailStateBase {
  /// The address a reply/forward is sent from: the originating account, so a
  /// mail received on account B is never answered from account A.
  String? _originatingFrom([Email? target]) {
    final email = target ?? _email;
    if (email == null || email.accountId.isEmpty) return null;
    return _repo.getAccount(email.accountId)?.email;
  }

  /// Opens `ComposeScreen` prefilled from the backend's compose context
  /// (`GET /api/mails/{id}/compose/{mode}`) instead of recomputing
  /// recipients/subject/threading client-side — see docs-dev spec §4.
  /// [mode] is `'reply'`, `'reply-all'` or `'forward'`.
  Future<void> _openComposePrefill(
    String mode, {
    required String title,
    Email? target,
  }) async {
    final email = target ?? _email;
    if (email == null || _composeActionBusy) return;
    setState(() => _composeActionBusy = true);
    final ComposePrefill prefill;
    try {
      prefill = await _repo.getComposePrefill(email.id, mode);
    } catch (error) {
      if (mounted) {
        setState(() => _composeActionBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10nNow.couldntPrepareTheReply(friendlyErrorMessage(error)),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _composeActionBusy = false);

    final isForward = mode == 'forward';
    final sender = prefill.originalFrom ?? email.senderEmail;
    final subject = prefill.originalSubject ?? email.subject;
    final formattedDate = prefill.originalDate == null
        ? null
        : formatMailDateFull(prefill.originalDate!);
    final originalHtml = email.bodyHtml?.trim().isNotEmpty == true
        ? email.bodyHtml!
        : htmlEscape.convert(email.bodyText).replaceAll('\n', '<br>');
    var initialBody = '';
    String? initialBodyHtml;
    var initialAttachments = const <Attachment>[];
    if (isForward) {
      final dateLine = formattedDate == null
          ? ''
          : l10nNow.forwardDateLine(formattedDate);
      initialBody = l10nNow.forwardedMessageFromSubject(
        sender,
        dateLine,
        subject,
        email.bodyText,
      );
      initialBodyHtml = l10nNow.forwardedMessageFromSubject2(
        htmlEscape.convert(sender),
        formattedDate == null
            ? ''
            : l10nNow.forwardDateLineHtml(htmlEscape.convert(formattedDate)),
        htmlEscape.convert(subject),
        originalHtml,
      );
      initialAttachments = prefill.attachments;
    } else {
      final attribution = formattedDate == null
          ? l10nNow.wroteSender(sender)
          : l10nNow.wroteOnDate(formattedDate, sender);
      initialBody =
          '\n\n$attribution\n> ${email.bodyText.replaceAll('\n', '\n> ')}';
      initialBodyHtml =
          '<p><br></p><p>${htmlEscape.convert(attribution)}</p>'
          '<blockquote>$originalHtml</blockquote>';
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          composeTitle: title,
          initialFrom: _originatingFrom(email),
          initialTo: prefill.to.join(', '),
          initialCc: prefill.cc.join(', '),
          initialSubject: prefill.suggestedSubject,
          initialBody: initialBody,
          initialBodyHtml: initialBodyHtml,
          initialAttachments: initialAttachments,
          attachmentSourceMailId: isForward ? email.id : null,
          initialThreadId: isForward ? null : email.threadId,
          inReplyToId: isForward ? null : email.id,
        ),
      ),
    );
    if (sent != true || !mounted) return;
    if (isForward) {
      await _repo.markAsForwarded([email.id]);
    } else {
      await _repo.markAsReplied([email.id]);
    }
  }

  Future<void> _reply() => _openComposePrefill('reply', title: l10nNow.reply);

  Future<void> _replyAll() =>
      _openComposePrefill('reply-all', title: l10nNow.replyAll);

  Future<void> _forward() =>
      _openComposePrefill('forward', title: l10nNow.forward);
}
