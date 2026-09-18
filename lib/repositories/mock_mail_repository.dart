import 'dart:math';

import 'package:flutter/material.dart';

import '../data/mock/mock_email_generator.dart';
import '../data/mock/mock_emails.dart';
import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../services/account_connection.dart';
import 'mail_repository.dart';

/// Fully functional in-memory implementation of [MailRepository].
///
/// All operations mutate an internal list and notify listeners, so the UI
/// updates after read/pin/trash/bulk actions. A short artificial delay makes
/// the loading states behave like a real network call. State is transient —
/// restarting the app resets it, which is fine for mock mode.
class MockMailRepository extends MailRepository {
  /// Documented mock account accepted by login while `AppConfig.useMockApi`
  /// is true. `nisa@kaydet.com` / `kaydet123`. Mock-only — no real account
  /// exists and nothing leaves the device.
  static const String demoEmail = 'nisa@kaydet.com';
  static const String demoPassword = 'kaydet123';

  static const Duration _latency = Duration(milliseconds: 350);

  MockMailRepository({AccountConnection? connection})
    : _connection = connection ?? MockAccountConnection() {
    resetMockData();
  }

  final AccountConnection _connection;

  final List<Email> _emails = [];
  final List<MailLabel> _labels = [];
  final List<MailAccount> _accounts = [];
  final Random _random = Random();

  String _currentUser = demoEmail;
  String? _activeAccountId;
  bool _loggedIn = false;
  bool _loading = false;

  /// Mails with no account stamp belong to the primary account. Keeps the
  /// seed/generator call sites untouched. Mails without a thread id get their
  /// own conversation (`t-<id>`), so old seed/generated mails remain valid
  /// and are never merged across unrelated senders/subjects.
  Email _stamped(Email email, String accountId) {
    final withAccount = email.accountId.isEmpty
        ? email.copyWith(accountId: accountId)
        : email;
    if (withAccount.threadId.isNotEmpty) return withAccount;
    return withAccount.copyWith(threadId: 't-${withAccount.id}');
  }

  /// Resets everything to a pristine single-account session for [email]:
  /// seed mailbox, default labels, one connected account, active mailbox.
  /// Logging in (or restoring a session) always lands on the signing-in
  /// user's own mailbox — a different user means different data, like the
  /// real backend will behave. Only the explicit add-account flow grows the
  /// account list.
  void _resetToSingleAccount(String email, {String? displayName}) {
    final account = MailAccount(
      email: email.trim(),
      displayName: displayName,
      provider: AccountProvider.inferFromEmail(email),
    );
    _emails
      ..clear()
      ..addAll(MockEmails.seed.map((e) => _stamped(e, account.id)));
    _labels
      ..clear()
      ..addAll(MockLabels.all);
    _accounts
      ..clear()
      ..add(account);
    _currentUser = account.email;
    _activeAccountId = account.id;
    _loggedIn = false;
    _loading = false;
  }

  /// Restores the pristine single-account dataset (emails, labels, accounts
  /// and active mailbox), discarding any changes made in the current session.
  /// Useful for tests and development; the normal app restart already resets
  /// mock state because it is never persisted anywhere.
  void resetMockData() {
    _resetToSingleAccount(demoEmail, displayName: 'Ben');
    notifyListeners();
  }

  Future<void> _delay() => Future<void>.delayed(_latency);

  void _replaceMany(List<String> ids, Email Function(Email) transform) {
    for (final id in ids) {
      final index = _emails.indexWhere((e) => e.id == id);
      if (index >= 0) _emails[index] = transform(_emails[index]);
    }
  }

  @override
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async {
    await _delay();
    // Simulated auth: any well-formed credentials are accepted. A login
    // starts a fresh single-account session for that user (see
    // [_resetToSingleAccount]); adding a second mailbox is only possible
    // through the explicit add-account flow.
    _resetToSingleAccount(email.trim(), displayName: 'Ben');
    _loggedIn = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> restoreSession(String email) async {
    _resetToSingleAccount(email.trim(), displayName: 'Ben');
    _loggedIn = true;
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    await _delay();
    _loggedIn = false;
    notifyListeners();
  }

  @override
  String get currentUser {
    final active = getAccount(_activeAccountId ?? '');
    if (active != null) return active.email;
    if (_accounts.isNotEmpty) return _accounts.first.email;
    return _currentUser;
  }

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  List<MailAccount> get accounts => List.unmodifiable(_accounts);

  @override
  String? get activeAccountId => _activeAccountId;

  @override
  Future<void> setActiveAccount(String? accountId) async {
    if (accountId == null) {
      _activeAccountId = null; // Unified mailbox.
    } else {
      if (getAccount(accountId) == null) return; // Unknown: never blank.
      _activeAccountId = getAccount(accountId)!.id;
    }
    _currentUser = currentUser;
    notifyListeners();
  }

  @override
  MailAccount? getAccount(String accountId) {
    final id = accountId.trim().toLowerCase();
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  @override
  Future<MailAccount> connectAccount({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim();
    final existing = getAccount(normalized);
    if (existing != null) {
      await setActiveAccount(existing.id);
      return existing;
    }
    final connected = await _connection.connect(
      email: normalized,
      password: password,
    );
    final account = MailAccount(
      email: connected.email,
      displayName: connected.displayName,
      provider: connected.provider,
    );
    _accounts.add(account);
    _emails.addAll(
      MockEmails.secondAccountSeed(account.email)
          .map((e) => _stamped(e, account.id)),
    );
    await setActiveAccount(account.id);
    return account;
  }

  @override
  Future<void> removeAccount(String accountId) async {
    final account = getAccount(accountId);
    if (account == null) return;
    if (_accounts.length <= 1) {
      throw StateError('Son hesap kaldırılamaz.');
    }
    await _delay();
    _emails.removeWhere((e) => e.accountId == account.id);
    _accounts.removeWhere((a) => a.id == account.id);
    if (_activeAccountId == account.id) {
      _activeAccountId = null; // Fall back to unified.
    }
    _currentUser = currentUser;
    notifyListeners();
  }

  /// Mails visible in the current mailbox scope: the active account's mails,
  /// or every account's mails when unified (`_activeAccountId == null`).
  Iterable<Email> get _scopedEmails {
    final active = _activeAccountId;
    if (active == null) return _emails;
    return _emails.where((e) => e.accountId == active);
  }

  /// Starred and pinned both surface in Yıldızlılar as one group.
  static bool _isHighlighted(Email e) => e.isPinned || e.isStarred;

  @override
  List<Email> getEmailsInFolder(MailFolder folder) {
    final result = folder == MailFolder.pinned
        ? _scopedEmails.where((e) => _isHighlighted(e)).toList()
        : _scopedEmails.where((e) => e.folder == folder).toList();
    // Highlighted mails float above the rest (no separate section — one
    // list); newest-first is preserved inside each group.
    result.sort((a, b) {
      final ha = _isHighlighted(a);
      final hb = _isHighlighted(b);
      if (ha != hb) return ha ? -1 : 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return List.unmodifiable(result);
  }

  @override
  List<Email> getAllEmails() {
    final all = [..._emails];
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(all);
  }

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async {
    if (_loading) return const [];
    _loading = true;
    await _delay();
    final generated = MockEmailGenerator.generateMoreEmails(
      count: 20,
      folder: folder,
      random: _random,
    );
    // Generated mails must not push the pinned total past the limit.
    var pinnedCount = _emails.where((e) => e.isPinned).length;
    final targets = _activeAccountId == null
        ? _accounts.map((a) => a.id).toList()
        : [_activeAccountId!];
    final batch = <Email>[];
    for (var i = 0; i < generated.length; i++) {
      var email = generated[i];
      if (email.isPinned && pinnedCount >= MailRepository.maxPinnedMails) {
        email = email.copyWith(isPinned: false, isStarred: false);
      } else {
        if (email.isPinned) pinnedCount++;
      }
      // Round-robin across the visible accounts so unified load-more feeds
      // every mailbox instead of biasing the first one.
      batch.add(_stamped(email, targets[i % targets.length]));
    }
    _emails.addAll(batch);
    _loading = false;
    notifyListeners();
    return batch;
  }

  @override
  Future<void> refreshEmails(MailFolder folder) async {
    // Simulate a network round-trip without mutating anything: the stored
    // mails (read/star/pin/folder state included) stay intact, listeners are
    // notified, and no new messages are invented per gesture, so a pull never
    // duplicates mail. No write path is shared with [_loading], so this can
    // never race `_loadMore`.
    await _delay();
    notifyListeners();
  }

  @override
  Future<Email?> getEmail(String id) async {
    await _delay();
    for (final e in _emails) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  List<Email> getThreadEmails(String threadId) {
    if (threadId.isEmpty) return const [];
    final thread = _emails.where((e) => e.threadId == threadId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(thread);
  }

  /// Which account a composed mail belongs to: explicit id first, then the
  /// sender address, then the active mailbox, then the first account.
  String _resolveAccountId(String? fromAccountId, String? from) {
    if (fromAccountId != null && getAccount(fromAccountId) != null) {
      return getAccount(fromAccountId)!.id;
    }
    if (from != null && getAccount(from) != null) {
      return getAccount(from)!.id;
    }
    if (_activeAccountId != null) return _activeAccountId!;
    return _accounts.first.id;
  }

  Email _createFromCompose({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subject,
    required String body,
    List<Attachment> attachments = const [],
    required MailFolder folder,
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
  }) {
    final accountId = _resolveAccountId(fromAccountId, from);
    final account = getAccount(accountId)!;
    final id =
        'composed-${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(1 << 32)}';
    final email = Email(
      id: id,
      senderName: account.displayName ?? 'Ben',
      senderEmail: from ?? account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      timestamp: DateTime.now(),
      isRead: true,
      folder: folder,
      attachments: attachments,
      accountId: accountId,
      // A reply reuses the caller's thread; a plain new mail starts its own.
      threadId: (threadId == null || threadId.isEmpty) ? 't-$id' : threadId,
      inReplyToId: inReplyToId,
    );
    _emails.add(email);
    return email;
  }

  @override
  Future<Email> sendEmail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
  }) async {
    await _delay();
    final email = _createFromCompose(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      attachments: attachments,
      folder: MailFolder.sent,
      from: from,
      fromAccountId: fromAccountId,
      threadId: threadId,
      inReplyToId: inReplyToId,
    );
    notifyListeners();
    return email;
  }

  @override
  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
  }) async {
    await _delay();
    final email = _createFromCompose(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      attachments: attachments,
      folder: MailFolder.drafts,
      from: from,
      fromAccountId: fromAccountId,
      threadId: threadId,
      inReplyToId: inReplyToId,
    );
    notifyListeners();
    return email;
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {
    await _delay();
    _replaceMany(
      ids,
      (e) => e.folder == MailFolder.trash
          ? e
          : e.copyWith(folder: MailFolder.trash),
    );
    notifyListeners();
  }

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(folder: folder));
    notifyListeners();
  }

  @override
  Future<void> markAsRead(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isRead: true));
    notifyListeners();
  }

  @override
  Future<void> markAsUnread(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isRead: false));
    notifyListeners();
  }

  /// Pins only while slots remain (see [MailRepository.maxPinnedMails]);
  /// extras are ignored. Unpinning always applies.
  List<String> _pinnableIds(List<String> ids) {
    var count = _emails.where((e) => e.isPinned).length;
    final allowed = <String>[];
    for (final id in ids) {
      final index = _emails.indexWhere((e) => e.id == id);
      if (index < 0) continue;
      if (_emails[index].isPinned) continue;
      if (count >= MailRepository.maxPinnedMails) continue;
      allowed.add(id);
      count++;
    }
    return allowed;
  }

  @override
  Future<void> setPinned(List<String> ids, bool pinned) async {
    await _delay();
    // Star and pin are independent flags: pinning never flips starred and
    // unpinning never clears it (and vice versa below).
    if (!pinned) {
      _replaceMany(ids, (e) => e.copyWith(isPinned: false));
    } else {
      _replaceMany(_pinnableIds(ids), (e) => e.copyWith(isPinned: true));
    }
    notifyListeners();
  }

  @override
  Future<void> setStarred(List<String> ids, bool starred) async {
    await _delay();
    // Starring is free: unlike pinning it consumes no pin slot.
    _replaceMany(ids, (e) => e.copyWith(isStarred: starred));
    notifyListeners();
  }

  @override
  Future<void> markAsReplied(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isReplied: true, isRead: true));
    notifyListeners();
  }

  @override
  Future<void> markAsForwarded(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isForwarded: true, isRead: true));
    notifyListeners();
  }

  /// Canonical name for duplicate checks: trimmed, Turkish 'İ' folded to 'i',
  /// lower-cased — "İŞ", "iş" and " İş " all compare equal.
  static String _canonicalName(String name) =>
      name.trim().replaceAll('İ', 'i').toLowerCase();

  void _assertLabelNameIsFree(String name, {String? selfId}) {
    final canonical = _canonicalName(name);
    if (canonical.isEmpty) {
      throw ArgumentError('Etiket adı boş olamaz.');
    }
    for (final label in _labels) {
      if (selfId != null && label.id == selfId) continue;
      if (_canonicalName(label.name) == canonical) {
        throw ArgumentError('Bu isimde bir etiket zaten var.');
      }
    }
  }

  @override
  List<MailLabel> getLabels() => List.unmodifiable(_labels);

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
  }) async {
    await _delay();
    _assertLabelNameIsFree(name);
    final label = MailLabel(
      id: 'label-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      color: color,
    );
    _labels.add(label);
    notifyListeners();
    return label;
  }

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) async {
    await _delay();
    final index = _labels.indexWhere((l) => l.id == id);
    if (index < 0) return; // Unknown label: nothing to update.
    _assertLabelNameIsFree(name, selfId: id);
    _labels[index] = MailLabel(id: id, name: name.trim(), color: color);
    notifyListeners();
  }

  @override
  Future<void> deleteLabel(String labelId) async {
    await _delay();
    if (!_labels.any((l) => l.id == labelId)) return;
    _labels.removeWhere((l) => l.id == labelId);
    // Strip the id from mails; the mails themselves stay untouched.
    _replaceMany(
      _emails
          .where((e) => e.labelIds.contains(labelId))
          .map((e) => e.id)
          .toList(),
      (e) => e.copyWith(
        labelIds: e.labelIds.where((id) => id != labelId).toList(),
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    await _delay();
    _replaceMany(emailIds, (e) {
      final updated = {...e.labelIds, ...labelIds}.toList();
      return e.copyWith(labelIds: updated);
    });
    notifyListeners();
  }

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    await _delay();
    final remove = labelIds.toSet();
    _replaceMany(emailIds, (e) {
      final updated = e.labelIds.where((id) => !remove.contains(id)).toList();
      return e.copyWith(labelIds: updated);
    });
    notifyListeners();
  }
}
