part of '../compose_screen.dart';

mixin _SignatureMixin on _ComposeStateBase, _RecipientsMixin {
  // --- Signature -------------------------------------------------------

  String _signatureSuffix(String signature) {
    if (signature.trim().isEmpty) return '';
    final beforeQuote = widget.initialReplyWritingLines > 0 ? '\n\n' : '';
    return '\n\n--\n$signature$beforeQuote';
  }

  bool get _signatureBodyUnchanged =>
      jsonEncode(_bodyController.document.toDelta().toJson()) ==
      _managedSignatureDelta;

  Future<void> _loadIdentities() async {
    final accountId = _resolvedFromAccountId;
    if (accountId == null) return;
    try {
      final identities = await _repo.listIdentities(accountId);
      if (!mounted || accountId != _resolvedFromAccountId) return;
      final wantedId = widget.initialIdentityId;
      final wantedAddress = widget.editingDraftId == null
          ? null
          : widget.initialFrom?.toLowerCase();
      setState(() {
        _identities = identities;
        _identitiesLoaded = true;
        _fromIdentity = wantedId != null
            ? identities
                  .where((identity) => identity.id == wantedId)
                  .firstOrNull
            : wantedAddress != null
            ? identities
                  .where(
                    (identity) =>
                        identity.emailAddress.toLowerCase() == wantedAddress,
                  )
                  .firstOrNull
            : identities.where((identity) => identity.isDefault).firstOrNull;
      });
      await _syncSignature();
    } catch (error) {
      if (!mounted || widget.initialIdentityId == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10nNow.couldntLoadTheSenderIdentity(friendlyErrorMessage(error)),
          ),
        ),
      );
    }
  }

  Future<void> _pickIdentity(MailIdentity identity) async {
    setState(() => _fromIdentity = identity);
    await _syncSignature();
  }

  /// Updates only the automatically managed signature, before reply history.
  /// Compare the full delta so sender changes preserve both real typing and
  /// formatting, including formatting-only edits.
  Future<void> _syncSignature() async {
    if (!_signatureEligible) return;
    final request = ++_signatureRequest;
    if (!_signatureBodyUnchanged) return;
    final expectedDelta = _managedSignatureDelta;
    final account = _fromAccount;
    final accountId = _resolvedFromAccountId;
    if (account == null || accountId == null) return;
    final legacy = _repo.accounts
        .where((a) => a.email == account)
        .firstOrNull
        ?.signature;
    final signature = await resolveComposeSignature(
      _repo,
      accountId: accountId,
      mode: widget.inReplyToId != null
          ? ComposeSignatureMode.reply
          : widget.attachmentSourceMailId != null
          ? ComposeSignatureMode.forward
          : ComposeSignatureMode.newMail,
      identity: _fromIdentity,
      legacySignature: legacy,
    );
    if (!mounted ||
        request != _signatureRequest ||
        _fromAccount != account ||
        _managedSignatureDelta != expectedDelta ||
        !_signatureBodyUnchanged) {
      return;
    }
    if (signature == _insertedSignature) return;
    setState(() {
      _bodyController.replaceText(
        _signatureInsertionOffset,
        _signatureSuffix(_insertedSignature).length,
        _signatureSuffix(signature),
        const TextSelection.collapsed(offset: 0),
      );
      _insertedSignature = signature;
      _managedSignatureDelta = jsonEncode(
        _bodyController.document.toDelta().toJson(),
      );
    });
  }

  Future<void> _pickTemplate() async {
    final accountId = _resolvedFromAccountId;
    if (accountId == null) return;
    final template = await showModalBottomSheet<MailTemplate>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TemplatePicker(accountId: accountId, repository: _repo),
    );
    if (template == null || !mounted || accountId != _resolvedFromAccountId) {
      return;
    }
    if (template.subject.isNotEmpty &&
        _subjectController.text.trim().isNotEmpty &&
        _subjectController.text.trim() != template.subject) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10nNow.replaceTheSubject),
          content: Text(l10nNow.theCurrentSubjectWillBe),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10nNow.keepSubject),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10nNow.replace),
            ),
          ],
        ),
      );
      if (replace == true) _subjectController.text = template.subject;
    } else if (_subjectController.text.trim().isEmpty) {
      _subjectController.text = template.subject;
    }
    if (!mounted) return;
    _insertReusableText(template.bodyText ?? '');
  }

  void _insertReusableText(String inserted) {
    if (inserted.isEmpty) return;
    final managedSignature = _signatureEligible && _signatureBodyUnchanged;
    final source = managedSignature ? _bodyBeforeSignature : _bodyText;
    final authoredEnd = managedSignature && widget.initialReplyWritingLines > 0
        ? _signatureInsertionOffset
        : source.length;
    final selection = _bodySelection;
    final selectionStart = selection.isValid
        ? selection.start.clamp(0, authoredEnd)
        : authoredEnd;
    final selectionEnd = selection.isValid
        ? selection.end.clamp(0, authoredEnd)
        : authoredEnd;
    final replaceEmpty = source.trim().isEmpty;
    final start = replaceEmpty ? 0 : selectionStart;
    final end = replaceEmpty ? source.length : selectionEnd;
    final updated = source.replaceRange(start, end, inserted);
    final cursor = start + inserted.length;
    setState(() {
      if (managedSignature) {
        _bodyBeforeSignature = updated;
        if (start <= _signatureInsertionOffset) {
          _signatureInsertionOffset += inserted.length - (end - start);
        }
      }
      _bodyController.replaceText(
        start,
        end - start,
        inserted,
        TextSelection.collapsed(offset: cursor),
      );
      if (managedSignature) {
        _managedSignatureDelta = jsonEncode(
          _bodyController.document.toDelta().toJson(),
        );
      }
    });
    _bodyFocus.requestFocus();
  }

  Future<void> _loadComposeLimits() async {
    final accountId = _resolvedFromAccountId;
    if (accountId == null) return;
    try {
      final limits = await _repo.composeLimits(accountId);
      if (mounted && accountId == _resolvedFromAccountId) {
        setState(() => _limits = limits);
      }
    } catch (_) {}
  }
}
