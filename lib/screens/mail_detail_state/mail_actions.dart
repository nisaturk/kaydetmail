part of '../mail_detail_screen.dart';

mixin _MailActionsMixin on _MailDetailStateBase, _ThreadLoadMixin, _ReplyMixin {
  /// Shows the pin-limit notice when no slot is left in [accountId]'s own
  /// cap (each account gets its own 3 slots — matches the backend's
  /// per-account enforcement). Returns true when the caller may proceed.
  bool _ensurePinSlot(String accountId) {
    final pinnedInAccount = _repo
        .getAllEmails()
        .where((email) => email.isPinned && email.accountId == accountId)
        .length;
    if (pinnedInAccount >= MailRepository.maxPinnedMails) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10nNow.youCanPinAtMost)));
      return false;
    }
    return true;
  }

  Future<void> _togglePin() async {
    final email = _email;
    if (email == null) return;
    if (!email.isPinned && !_ensurePinSlot(email.accountId)) return;
    _watchBackgroundMutation(_repo.setPinned([email.id], !email.isPinned));
  }

  Future<void> _toggleStar() async {
    final email = _email;
    if (email == null) return;
    // Star and pin are independent flags: starring never pins, unstarring
    // never unpins. Starring consumes no pin slot.
    _watchBackgroundMutation(_repo.setStarred([email.id], !email.isStarred));
  }

  /// Snoozed mail is hidden from normal folder views until its backend-owned
  /// deadline. State changes locally immediately while the backend request
  /// continues in the background.
  Future<void> _toggleSnooze() async {
    final email = _email;
    if (email == null) return;
    if (_repo.snoozedUntilOf(email.id) != null) {
      _watchBackgroundMutation(_repo.setSnoozed([email.id], null));
      return;
    }
    final until = await showSnoozePicker(context);
    if (until == null || !mounted) return;
    _watchBackgroundMutation(_repo.setSnoozed([email.id], until));
    unawaited(Navigator.of(context).maybePop().then<void>((_) {}));
  }

  Future<void> _moveMail() async {
    final email = _email;
    if (email == null) return;
    final target = await showMoveFolderSheet(
      context,
      repository: _repo,
      accountIds: {email.accountId},
      currentFolders: widget.currentCustomFolderId == null
          ? {email.folder}
          : const {},
      currentCustomFolderId: widget.currentCustomFolderId,
    );
    if (target == null || !mounted) return;
    final custom = target.customFolder;
    final operation = custom != null
        ? _repo.moveToCustomFolder(
            [email.id],
            accountId: custom.accountId,
            folderId: custom.folderId,
          )
        : target.folder == MailFolder.trash
        ? _repo.moveToTrash([email.id])
        : _repo.moveToFolder([email.id], target.folder!);
    _watchBackgroundMutation(
      operation,
      successMessage: l10nNow.emailMovedTo(target.label),
    );
    unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
  }

  /// Moves the open mail back to the inbox. For a mail whose current
  /// folder is Trash or Spam, `MailRepository.moveToFolder` resolves this
  /// to the backend's restore action (the mail's original pre-trash/spam
  /// folder), not a literal move to Inbox — see the repository doc
  /// comment. Restore / "Spam değil" / "Arşivden çıkar" all reduce to
  /// this one call.
  Future<void> _moveToInbox(String successMessage) async {
    final email = _email;
    if (email == null) return;
    _watchBackgroundMutation(
      _repo.moveToFolder([email.id], MailFolder.inbox),
      successMessage: successMessage,
    );
    unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
  }

  /// Folder-specific primary action for the open mail, when its current
  /// folder has one: Trash → restore, Spam → not spam, Archive →
  /// unarchive. Drafts open `ComposeScreen` instead of this screen (see
  /// `_onMailTap` in inbox/search screens), so `MailFolder.drafts` is not
  /// expected here — the `default` branch still returns null instead of
  /// assuming, so a draft opened by some future path degrades gracefully
  /// rather than crashing.
  IconButton? _folderAction(Email email) {
    switch (email.folder) {
      case MailFolder.trash:
        return IconButton(
          onPressed: () => _moveToInbox(l10nNow.emailRestored),
          tooltip: l10nNow.restore2,
          icon: const Icon(LucideIcons.rotateCcw),
        );
      case MailFolder.spam:
        return IconButton(
          onPressed: () => _moveToInbox(l10nNow.emailMarkedAsNotSpam),
          tooltip: l10nNow.notSpam,
          icon: const Icon(LucideIcons.shieldOff),
        );
      case MailFolder.archive:
        return IconButton(
          onPressed: () => _moveToInbox(l10nNow.emailUnarchived),
          tooltip: l10nNow.unarchive,
          icon: const Icon(LucideIcons.archiveRestore),
        );
      default:
        return null;
    }
  }

  /// Expunge stays visible until server confirms deletion.
  Future<void> _deleteForever() async {
    final ids = idsInFolder(_repo, _conversationIds, MailFolder.trash);
    if (ids.isEmpty) return;
    final confirmed = await confirmPermanentDelete(context, ids.length);
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.deletePermanently(ids);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10nNow.emailPermanentlyDeleted)),
      );
      await Navigator.of(context).maybePop();
    } catch (error) {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10nNow.actionFailed(friendlyErrorMessage(error))),
          ),
        );
      }
    }
  }
}
