part of '../compose_screen.dart';

mixin _SendMixin
    on
        _ComposeStateBase,
        _RecipientsMixin,
        _AttachmentsMixin,
        _SignatureMixin,
        _DraftMixin {
  DateTime? _lastScheduleAt;

  /// Commits pending recipient text into chips, then validates there is at
  /// least one To recipient and every chip looks like a real address.
  /// Shared by [_send] and [_scheduleSend].
  bool _validateRecipients() {
    setState(() {
      _commitPendingRecipient(_toRecipients, _toInputController);
      _commitPendingRecipient(_ccRecipients, _ccInputController);
      _commitPendingRecipient(_bccRecipients, _bccInputController);
    });
    if (_toRecipients.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10nNow.youMustEnterAtLeast)));
      _toFocus.requestFocus();
      return false;
    }
    final allRecipients = [
      ..._toRecipients,
      ..._ccRecipients,
      ..._bccRecipients,
    ];
    if (allRecipients.any((r) => !r.valid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nNow.fixTheInvalidEmailAddresses)),
      );
      _toFocus.requestFocus();
      return false;
    }
    return true;
  }

  /// Persist the full message before leaving compose and starting undo.
  /// A storage failure leaves the editor open.
  Future<void> _send() async {
    if (_sending) return;
    if (!_validateRecipients()) return;
    if (!_validateAttachmentsReady()) return;
    if (!_validateAttachmentLimits()) return;
    final to = _addressStrings(_toRecipients);
    final cc = _addressStrings(_ccRecipients);
    final bcc = _addressStrings(_bccRecipients);
    final subject = _subjectController.text.trim();
    final body = _outgoingBodyText;
    final bodyHtml = _bodyHtml;
    final attachments = List<Attachment>.unmodifiable(_attachments);
    final from = _fromAccount;
    final identityId = _fromIdentity?.id;
    final fromAccountId = _resolvedFromAccountId;
    final threadId = widget.initialThreadId;
    final inReplyToId = widget.inReplyToId;
    final draftId = _draftId;
    final requestReadReceipt = _requestReadReceipt;
    final composeTitle = widget.composeTitle;

    final pending = PendingSend(
      id: PendingSendQueue.instance.nextId(),
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      bodyHtml: bodyHtml,
      attachments: attachments,
      from: from,
      fromAccountId: fromAccountId,
      threadId: threadId,
      inReplyToId: inReplyToId,
      identityId: identityId,
      requestReadReceipt: requestReadReceipt,
      draftId: draftId,
    );

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await PendingSendQueue.instance.enqueue(
        pending,
        messenger: messenger,
        replacesId: widget.replacesOutboxId,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10nNow.couldntSaveTheMessage(friendlyErrorMessage(error)),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final undoWindow = PendingSendQueue.undoWindow;
    if (undoWindow > Duration.zero) {
      final controller = messenger.showSnackBar(
        SnackBar(
          key: const Key('undo-send-snackbar'),
          duration: undoWindow,
          content: UndoSendSnackContent(duration: undoWindow),
          action: SnackBarAction(
            label: l10nNow.undo,
            onPressed: () {
              if (!PendingSendQueue.instance.cancel(pending.id)) return;
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => ComposeScreen(
                    composeTitle: composeTitle,
                    editingDraftId: draftId,
                    insertSignature: false,
                    initialFrom: from,
                    initialTo: to.join(', '),
                    initialCc: cc.join(', '),
                    initialBcc: bcc.join(', '),
                    initialSubject: subject,
                    initialBody: body,
                    initialBodyHtml: bodyHtml,
                    initialAttachments: attachments,
                    initialThreadId: threadId,
                    inReplyToId: inReplyToId,
                    initialIdentityId: identityId,
                    initialRequestReadReceipt: requestReadReceipt,
                  ),
                ),
              );
            },
          ),
        ),
      );
      var undoClosed = false;
      unawaited(controller.closed.then((_) => undoClosed = true));
      unawaited(
        Future<void>.delayed(undoWindow, () {
          if (!undoClosed) controller.close();
        }),
      );
    }

    navigator.pop(true);
  }

  void _toggleReadReceipt() {
    setState(() => _requestReadReceipt = !_requestReadReceipt);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _requestReadReceipt
                ? l10nNow.aReadReceiptWillBe
                : l10nNow.aReadReceiptWontBe,
          ),
        ),
      );
  }

  /// Opens the address book (device, saved and recently seen contacts —
  /// the same set the recipient autocomplete searches) and adds the picked
  /// addresses as chips to the chosen field, skipping ones already there.
  Future<void> _pickFromContacts() async {
    if (_sending) return;
    _removeSuggestionOverlay();
    _refreshContacts();
    final picked = await showModalBottomSheet<ContactPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ContactPickerSheet(contacts: _contacts),
    );
    if (picked == null || picked.contacts.isEmpty || !mounted) return;
    final recipients = switch (picked.field) {
      RecipientField.to => _toRecipients,
      RecipientField.cc => _ccRecipients,
      RecipientField.bcc => _bccRecipients,
    };
    setState(() {
      final existing = {for (final r in recipients) r.address.toLowerCase()};
      for (final contact in picked.contacts) {
        if (!existing.add(contact.email.toLowerCase())) continue;
        recipients.add(
          Recipient(
            contact.email,
            valid: emailShapePattern.hasMatch(contact.email),
          ),
        );
      }
      if (picked.field == RecipientField.cc) _ccExpanded = true;
      if (picked.field == RecipientField.bcc) _bccExpanded = true;
    });
  }

  /// Offered from the compose overflow menu: picks a future date/time
  /// through the standard pickers, then queues the mail with
  /// `MailRepository.scheduleSend` instead of sending it now.
  Future<void> _scheduleSend() async {
    if (_sending) return;
    if (!_validateRecipients()) return;
    if (!_validateAttachmentsReady()) return;
    if (!_validateAttachmentLimits()) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _lastScheduleAt?.isAfter(now) == true
          ? _lastScheduleAt!
          : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _lastScheduleAt?.isAfter(now) == true
            ? _lastScheduleAt!
            : now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    final sendAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!sendAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10nNow.pleaseChooseAFutureDate)));
      return;
    }
    _lastScheduleAt = sendAt;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    try {
      await _repo.scheduleSend(
        to: _addressStrings(_toRecipients),
        cc: _addressStrings(_ccRecipients),
        bcc: _addressStrings(_bccRecipients),
        subject: _subjectController.text.trim(),
        body: _outgoingBodyText,
        bodyHtml: _bodyHtml,
        attachments: List.unmodifiable(_attachments),
        from: _fromAccount,
        fromAccountId: _resolvedFromAccountId,
        inReplyToId: widget.inReplyToId,
        identityId: _fromIdentity?.id,
        requestReadReceipt: _requestReadReceipt,
        sendAt: sendAt,
      );
      final draftId = _draftId;
      if (draftId != null) {
        try {
          await _repo.deleteDraft(draftId);
        } catch (_) {
          // Scheduled already; a stale draft row reconciles on next refresh.
        }
      }
      if (!mounted) return;
      navigator.pop(true);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10nNow.theEmailIsScheduledTo(formatMailDateFull(sendAt)),
            ),
          ),
        );
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(l10nNow.couldntSchedule(friendlyErrorMessage(e))),
            ),
          );
      }
    }
  }
}
