import 'dart:convert';

import '../../models/manual_contact.dart';
import '../../services/api_exception.dart';
import '../../utils/idempotency_key.dart';
import 'account_session.dart';
import 'repository_context.dart';

/// Manually-added contacts: backend-owned, cached on the device and queued
/// while offline (locally created ones carry [localIdPrefix] ids until the
/// backend confirms them).
class ContactModule {
  ContactModule(this._ctx);

  final RepositoryContext _ctx;

  static const localIdPrefix = 'local-contact-';

  void _assertContactEmailIsValid(
    AccountSession session,
    String email, {
    String? selfId,
  }) {
    if (email.isEmpty || !email.contains('@')) {
      throw ArgumentError('Geçerli bir e-posta adresi girin.');
    }
    final canonical = email.toLowerCase();
    if (session.manualContacts.any(
      (c) => c.id != selfId && c.email.toLowerCase() == canonical,
    )) {
      throw ArgumentError('Bu e-posta zaten kayıtlı.');
    }
  }

  Future<void> persist(AccountSession session) async {
    final store = session.flagsStore;
    if (store == null) return;
    await store.writeContacts([
      for (final c in session.manualContacts)
        {'id': c.id, 'email': c.email, 'displayName': c.displayName},
    ]);
  }

  /// The session that owns manual contact [id], if any.
  AccountSession? _sessionForManualContact(String id) {
    for (final s in _ctx.registry.sessions.values) {
      if (s.manualContacts.any((c) => c.id == id)) return s;
    }
    return null;
  }

  /// Manually-added contacts from every account in scope — the unified
  /// view unions them (dedup by id; account-local ids never collide in
  /// practice), same shape as [getLabels].
  List<ManualContact> getManualContacts() {
    final seen = <String>{};
    final result = <ManualContact>[];
    for (final session in _ctx.registry.scoped) {
      for (final c in session.manualContacts) {
        if (seen.add(c.id)) result.add(c);
      }
    }
    return List.unmodifiable(result);
  }

  List<ManualContact> getManualContactsForAccount(String accountId) =>
      List.unmodifiable(
        _ctx.registry.sessions[accountId]?.manualContacts ??
            const <ManualContact>[],
      );

  Future<ManualContact> addManualContact({
    required String email,
    String? displayName,
    String? accountId,
  }) async {
    final session = accountId != null
        ? _ctx.registry.forAccount(accountId)
        : _ctx.registry.primary;
    final trimmedEmail = email.trim();
    final trimmedName = displayName?.trim();
    final name = (trimmedName == null || trimmedName.isEmpty)
        ? null
        : trimmedName;
    _assertContactEmailIsValid(session, trimmedEmail);
    Map<String, dynamic> created;
    try {
      created = await session.mailService.createContact(trimmedEmail, name);
    } on ApiException catch (e) {
      if (e.code == 'contact_already_exists') {
        throw ArgumentError('Bu e-posta zaten kayıtlı.');
      }
      if (!_ctx.isOfflineFailure(e)) rethrow;
      _ctx.markOffline(session);
      created = {
        'id': '$localIdPrefix${newIdempotencyKey()}',
        'email': trimmedEmail,
        'displayName': name,
      };
      await _queueContactMutation(
        session,
        created['id'] as String,
        'contact_create',
        created,
      );
    }
    final contact = ManualContact(
      id: created['id'] as String,
      accountId: session.account.id,
      email: created['email'] as String,
      displayName: created['displayName'] as String?,
    );
    session.manualContacts = [...session.manualContacts, contact];
    await persist(session);
    _ctx.notify();
    return contact;
  }

  Future<void> updateManualContact({
    required String id,
    required String email,
    String? displayName,
  }) async {
    final session = _sessionForManualContact(id);
    if (session == null) return;
    final index = session.manualContacts.indexWhere((c) => c.id == id);
    if (index < 0) return;
    final trimmedEmail = email.trim();
    final trimmedName = displayName?.trim();
    final name = (trimmedName == null || trimmedName.isEmpty)
        ? null
        : trimmedName;
    _assertContactEmailIsValid(session, trimmedEmail, selfId: id);
    Map<String, dynamic> updated = {'email': trimmedEmail, 'displayName': name};
    if (id.startsWith(localIdPrefix)) {
      await _queueContactMutation(session, id, 'contact_create', updated);
    } else {
      try {
        updated = await session.mailService.updateContact(
          id,
          trimmedEmail,
          name,
        );
        await session.flagsStore?.clearQueuedMutation(id, 'contact');
      } on ApiException catch (e) {
        if (e.code == 'contact_already_exists') {
          throw ArgumentError('Bu e-posta zaten kayıtlı.');
        }
        if (!_ctx.isOfflineFailure(e)) rethrow;
        _ctx.markOffline(session);
        await _queueContactMutation(session, id, 'contact_update', updated);
      }
    }
    session.manualContacts = [...session.manualContacts]
      ..[index] = ManualContact(
        id: id,
        accountId: session.account.id,
        email: updated['email'] as String,
        displayName: updated['displayName'] as String?,
      );
    await persist(session);
    _ctx.notify();
  }

  Future<void> deleteManualContact(String id) async {
    final session = _sessionForManualContact(id);
    if (session == null) return;
    final store = session.flagsStore;
    if (id.startsWith(localIdPrefix)) {
      await store?.clearQueuedMutation(id, 'contact');
    } else {
      try {
        await session.mailService.deleteContact(id);
        await store?.clearQueuedMutation(id, 'contact');
      } catch (error) {
        if (!_ctx.isOfflineFailure(error)) return;
        _ctx.markOffline(session);
        await store?.queueMutation(id, 'contact_delete');
      }
    }
    session.manualContacts = session.manualContacts
        .where((c) => c.id != id)
        .toList();
    await persist(session);
    _ctx.notify();
  }

  Future<void> _queueContactMutation(
    AccountSession session,
    String id,
    String operation,
    Map<String, dynamic> contact,
  ) async {
    await session.flagsStore?.queueMutation(
      id,
      operation,
      folderId: jsonEncode({
        'email': contact['email'],
        'displayName': contact['displayName'],
      }),
    );
  }
}
