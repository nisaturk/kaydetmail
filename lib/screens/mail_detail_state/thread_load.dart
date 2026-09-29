part of '../mail_detail_screen.dart';

mixin _ThreadLoadMixin on _MailDetailStateBase, _ReplyMixin {
  void _watchBackgroundMutation(
    Future<void> operation, {
    String? successMessage,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    unawaited(() async {
      try {
        await operation;
        if (successMessage != null && messenger.mounted) {
          messenger.showSnackBar(SnackBar(content: Text(successMessage)));
        }
      } catch (error) {
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
            ),
          );
        }
      }
    }());
  }

  /// Repository notifications already carry local optimistic state; fetching
  /// detail on every flag change would trigger an avoidable IMAP round trip.
  void _syncCachedMail() {
    if (!mounted || _email == null) return;
    for (final email in _repo.getAllEmails()) {
      if (email.id != widget.emailId) continue;
      // Other messages may have changed star/read state even if opened mail
      // itself is identical; rebuild history from the repository snapshot.
      setState(() {
        _email = email;
        _thread = _mergeThread(email, [
          ..._fetchedThread.where((e) => e.threadId == email.threadId),
          ..._repo.getThreadEmails(email.threadId),
        ]);
      });
      return;
    }
  }

  /// Mail-first loading: the opened mail renders as soon as its own detail
  /// response arrives. Thread enrichment follows asynchronously and can only
  /// *add* messages — it never replaces or blanks the loaded mail.
  ///
  /// Listener-safe: a failed refresh keeps the already-shown mail instead
  /// of clearing it; the spinner only shows on the very first load and on
  /// explicit retry.
  Future<void> _reload() async {
    Email? email;
    Object? error;
    try {
      email = await _repo.getEmail(widget.emailId);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    if (email != null) {
      final loaded = email;
      final first = !_opened;
      setState(() {
        _email = loaded;
        _thread = _mergeThread(loaded, [
          ..._fetchedThread.where((e) => e.threadId == loaded.threadId),
          ..._repo.getThreadEmails(loaded.threadId),
        ]);
        _loading = false;
        _loadError = null;
      });

      // A freshly opened mail becomes read — but only on the very first
      // load. Later reloads (pin, mark-as-unread) must not silently flip
      // it back.
      if (first) {
        _opened = true;
        if (widget.openReplyOnLoad) unawaited(_reply());
        if (!loaded.isRead) {
          _watchBackgroundMutation(_repo.markAsRead([loaded.id]));
        }
      }
      _maybeEnrichThread(loaded);
    } else if (_email == null) {
      // Nothing shown yet: surface not-found vs. transport error.
      if (error != null) debugPrint('Mail detail load failed: $error');
      setState(() {
        _loading = false;
        _loadError = error;
      });
    } else if (error != null) {
      // Refresh failed but the loaded mail stays on screen.
      debugPrint('Mail detail refresh failed: $error');
    }
  }

  /// Server conversation order breaks timestamp ties; until enrichment,
  /// equal-time cache entries cannot safely be identified as older.
  List<Email> _mergeThread(Email email, List<Email> others) {
    final positions = <String, int>{
      for (var i = 0; i < _fetchedThread.length; i++) _fetchedThread[i].id: i,
    };
    final openedIndex = positions[email.id];
    final byId = {for (final message in others) message.id: message}
      ..remove(email.id);
    final older =
        byId.values.where((message) {
          final index = positions[message.id];
          if (openedIndex != null && index != null) return index < openedIndex;
          return message.timestamp.isBefore(email.timestamp);
        }).toList()..sort((a, b) {
          final byDate = b.timestamp.compareTo(a.timestamp);
          if (byDate != 0) return byDate;
          return (positions[b.id] ?? -1).compareTo(positions[a.id] ?? -1);
        });
    return List.unmodifiable([email, ...older]);
  }

  /// Kicks off conversation enrichment once per mail+thread. A failure only
  /// keeps the already-rendered single mail — the screen never blanks and
  /// the spinner never returns.
  void _maybeEnrichThread(Email email) {
    if (email.threadId.isEmpty) return;
    final key = '${email.id}@${email.threadId}';
    if (key == _enrichedKey || key == _enrichingKey) return;
    _enrichingKey = key;
    unawaited(_enrichThread(email, key));
  }

  Future<void> _enrichThread(Email email, String key) async {
    try {
      final fetched = await _repo.fetchThreadEmails(email.threadId);
      if (!mounted) return;
      // The user may have navigated to another mail meanwhile — only merge
      // into the mail this fetch started for.
      if (_email?.id != email.id) return;
      // The server conversation can lag behind replies sent from this app
      // (only a local copy exists until the next sync), so keep those too.
      _fetchedThread = fetched;
      final merged = _mergeThread(email, [
        ...fetched,
        ..._repo.getThreadEmails(email.threadId),
      ]);
      debugPrint('Thread ${email.threadId}: ${merged.length} messages');
      if (!_sameIds(merged, _thread)) {
        setState(() => _thread = merged);
      }
      _enrichedKey = key;
    } catch (e) {
      debugPrint('Thread enrichment failed for ${email.threadId}: $e');
    } finally {
      if (_enrichingKey == key) _enrichingKey = null;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    await _reload();
  }
}
