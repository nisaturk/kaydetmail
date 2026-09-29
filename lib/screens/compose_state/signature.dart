part of '../compose_screen.dart';

mixin _SignatureMixin on _ComposeStateBase, _RecipientsMixin {
  // --- Signature -------------------------------------------------------

  String _signatureSuffix(String signature) =>
      signature.trim().isEmpty ? '' : '\n\n--\n$signature';

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
    } catch (error) {
      if (!mounted || widget.initialIdentityId == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gönderen kimliği yüklenemedi: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _pickIdentity(MailIdentity identity) async {
    setState(() => _fromIdentity = identity);
    await _syncSignature();
  }

  /// Applies the signature for the current Kimden account and compose mode
  /// (new/reply/forward default, or the chosen identity's own signature), but
  /// only while the body still exactly matches [_bodyBeforeSignature] plus
  /// whatever signature was last inserted — i.e. the user hasn't typed
  /// anything else since. Called once on open and again every time Kimden
  /// changes, so a switch re-applies the new account's signature without
  /// ever clobbering real typing.
  Future<void> _syncSignature() async {
    if (!_signatureEligible) return;
    final expected =
        _bodyBeforeSignature + _signatureSuffix(_insertedSignature);
    if (_bodyText != expected) return;
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
    if (!mounted || _fromAccount != account || _bodyText != expected) return;
    setState(() {
      _bodyController.replaceText(
        _bodyBeforeSignature.length,
        _signatureSuffix(_insertedSignature).length,
        _signatureSuffix(signature),
        const TextSelection.collapsed(offset: 0),
      );
      _insertedSignature = signature;
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
          title: const Text('Konuyu değiştir?'),
          content: const Text(
            'Mevcut konu hazır metindeki konuyla değiştirilecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Konuyu koru'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Değiştir'),
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
    final signature = _signatureSuffix(_insertedSignature);
    final managedSignature =
        _signatureEligible && _bodyText == _bodyBeforeSignature + signature;
    final source = managedSignature ? _bodyBeforeSignature : _bodyText;
    final selection = _bodySelection;
    final selectionStart = selection.isValid
        ? selection.start.clamp(0, source.length)
        : source.length;
    final selectionEnd = selection.isValid
        ? selection.end.clamp(0, source.length)
        : source.length;
    final replaceEmpty = source.trim().isEmpty;
    final start = replaceEmpty ? 0 : selectionStart;
    final end = replaceEmpty ? source.length : selectionEnd;
    final updated = source.replaceRange(start, end, inserted);
    final cursor = start + inserted.length;
    setState(() {
      if (managedSignature) _bodyBeforeSignature = updated;
      _bodyController.replaceText(
        start,
        end - start,
        inserted,
        TextSelection.collapsed(offset: cursor),
      );
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
