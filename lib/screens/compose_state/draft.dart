part of '../compose_screen.dart';

mixin _DraftMixin
    on _ComposeStateBase, _RecipientsMixin, _AttachmentsMixin, _SignatureMixin {
  Future<bool> _onWillPop() async {
    // A draft already on the server (opened for editing, or saved from the
    // overflow menu) is kept in sync on exit instead of asking again.
    if (_draftId != null) {
      if (!_draftChanged) return true;
      final saved = await _saveDraft();
      if (!mounted) return false;
      if (saved) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taslak kaydedilemedi. Tekrar deneyin.')),
      );
      return false;
    }
    if (!_hasContent) return true;
    var saving = false;
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.space5,
                  AppTheme.space3,
                  AppTheme.space5,
                  AppTheme.space5 +
                      MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.colors(sheetContext).border,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.space5),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                      ),
                      child: const Icon(LucideIcons.filePenLine, size: 22),
                    ),
                    const SizedBox(height: AppTheme.space4),
                    Text(
                      'Bu taslak ne olsun?',
                      style: AppTheme.titleText.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      'Yazdıklarınızı daha sonra tamamlamak için kaydedebilir '
                      'veya taslağı kalıcı olarak silebilirsiniz.',
                      style: AppTheme.bodyText2.copyWith(
                        color: AppTheme.colors(sheetContext).secondaryText,
                      ),
                    ),
                    const SizedBox(height: AppTheme.space6),
                    FilledButton.icon(
                      key: const Key('save-draft-on-exit'),
                      onPressed: saving
                          ? null
                          : () async {
                              setSheetState(() => saving = true);
                              final saved = await _saveDraft();
                              if (!mounted || !sheetContext.mounted) return;
                              if (!saved) {
                                setSheetState(() => saving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Taslak kaydedilemedi. İçeriğiniz '
                                      'ekranda tutuluyor.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(sheetContext).pop(true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Taslak kaydedildi.'),
                                ),
                              );
                            },
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.save, size: 19),
                      label: Text(saving ? 'Kaydediliyor…' : 'Taslağı Kaydet'),
                    ),
                    const SizedBox(height: AppTheme.space2),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('discard-draft-on-exit'),
                        onPressed: saving
                            ? null
                            : () => Navigator.of(sheetContext).pop(true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.colors(sheetContext)
                              .destructive,
                          side: BorderSide(
                            color: AppTheme.colors(sheetContext).destructive,
                          ),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusLarge,
                            ),
                          ),
                        ),
                        icon: const Icon(LucideIcons.trash2, size: 19),
                        label: const Text('Taslağı Sil'),
                      ),
                    ),
                    const SizedBox(height: AppTheme.space1),
                    Center(
                      child: TextButton(
                        key: const Key('continue-editing-draft'),
                        onPressed: saving
                            ? null
                            : () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Düzenlemeye devam et'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ) ??
        false;
  }

  /// "Sil" from the overflow menu: throws the message away. A draft that
  /// already exists on the server is deleted there too; a message with
  /// content asks first, an empty one just closes.
  Future<void> _discard() async {
    if (_sending) return;
    final draftId = _draftId;
    final navigator = Navigator.of(context);
    if (draftId == null && !_hasContent) {
      navigator.pop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          draftId == null ? 'E-posta silinsin mi?' : 'Taslak silinsin mi?',
        ),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            key: const Key('confirm-discard'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Sil',
              style: TextStyle(
                color: AppTheme.colors(dialogContext).destructive,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (draftId == null) {
      navigator.pop();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await _repo.deleteDraft(draftId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Taslak silinemedi: ${friendlyErrorMessage(error)}'),
        ),
      );
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Taslak silindi.')));
    navigator.pop();
  }

  Future<void> _saveDraftFromMenu() async {
    if (_sending || !_hasContent) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await _saveDraft();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Taslak kaydedildi.'
              : 'Taslak kaydedilemedi. Tekrar deneyin.',
        ),
      ),
    );
  }

  Future<bool> _saveDraft() =>
      _pendingSave ??= _writeDraft().whenComplete(() => _pendingSave = null);

  Future<bool> _writeDraft() async {
    if (!_hasContent && _draftId == null) return true;
    if (!_attachmentsReady) return false;
    setState(() {
      _commitPendingRecipient(_toRecipients, _toInputController);
      _commitPendingRecipient(_ccRecipients, _ccInputController);
      _commitPendingRecipient(_bccRecipients, _bccInputController);
    });
    final fingerprint = _draftFingerprint;
    try {
      final saved = await _repo.saveDraft(
        from: _fromAccount,
        fromAccountId: _resolvedFromAccountId,
        identityId: _fromIdentity?.id,
        to: _addressStrings(_toRecipients),
        cc: _addressStrings(_ccRecipients),
        bcc: _addressStrings(_bccRecipients),
        subject: _subjectController.text.trim(),
        body: _outgoingBodyText,
        bodyHtml: _bodyHtml,
        attachments: List.unmodifiable(_attachments),
        threadId: widget.initialThreadId,
        inReplyToId: widget.inReplyToId,
        draftId: _draftId,
        onSyncFailure: (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Taslak yerel olarak kaydedildi; sunucu eşitlemesi başarısız.',
              ),
            ),
          );
        },
      );
      _draftId = saved.id;
      _savedDraftFingerprint = fingerprint;
      return true;
    } catch (_) {
      return false;
    }
  }
}
