import 'package:flutter/foundation.dart';

import '../../models/mail_signature.dart';
import '../../services/signature_store.dart';
import 'account_session.dart';
import 'session_registry.dart';

/// Account signatures, sender identities and the account's single legacy
/// signature. Backend-owned; each [AccountSession] caches the last fetch.
class SignatureModule {
  SignatureModule(this._registry, this._notify);

  final SessionRegistry _registry;
  final VoidCallback _notify;

  Future<List<MailSignature>> listSignatures(
    String accountId, {
    bool refresh = false,
  }) async {
    final session = _registry.forAccount(accountId);
    if (!refresh && session.signatures != null) return session.signatures!;
    final result = await session.mailService.getSignatures();
    session.signatures = [
      for (final signature in result.items)
        signature.copyWith(accountId: accountId),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    session.signatureDefaults = result.defaults;
    return session.signatures!;
  }

  Future<SignatureDefaults> getSignatureDefaults(String accountId) async {
    final session = _registry.forAccount(accountId);
    if (session.signatureDefaults != null) return session.signatureDefaults!;
    await listSignatures(accountId, refresh: true);
    return session.signatureDefaults ?? const SignatureDefaults();
  }

  Future<MailSignature> createSignature(
    String accountId,
    MailSignature signature,
  ) async {
    final session = _registry.forAccount(accountId);
    final created = (await session.mailService.createSignature(signature))
        .copyWith(accountId: accountId);
    final items = session.signatures ?? <MailSignature>[];
    session.signatures = [...items, created]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _notify();
    return created;
  }

  Future<MailSignature> updateSignature(
    String accountId,
    MailSignature signature,
  ) async {
    final session = _registry.forAccount(accountId);
    final updated = (await session.mailService.updateSignatureItem(signature))
        .copyWith(accountId: accountId);
    if (session.signatures != null) {
      session.signatures = [
        for (final item in session.signatures!)
          if (item.id == updated.id) updated else item,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    _notify();
    return updated;
  }

  Future<void> deleteSignature(String accountId, String signatureId) async {
    final session = _registry.forAccount(accountId);
    await session.mailService.deleteSignature(signatureId);
    session.signatures?.removeWhere((item) => item.id == signatureId);
    _notify();
  }

  Future<SignatureDefaults> updateSignatureDefaults(
    String accountId,
    SignatureDefaults defaults,
  ) async {
    final session = _registry.forAccount(accountId);
    final updated = await session.mailService.updateSignatureDefaults(defaults);
    session.signatureDefaults = updated;
    _notify();
    return updated;
  }

  Future<List<MailIdentity>> listIdentities(
    String accountId, {
    bool refresh = false,
  }) async {
    final session = _registry.forAccount(accountId);
    if (!refresh && session.identities != null) return session.identities!;
    final identities = await session.mailService.getIdentities();
    session.identities =
        [
          for (final identity in identities)
            identity.copyWith(accountId: accountId),
        ]..sort((a, b) {
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return a.emailAddress.toLowerCase().compareTo(
            b.emailAddress.toLowerCase(),
          );
        });
    return session.identities!;
  }

  Future<MailIdentity> createIdentity(
    String accountId,
    MailIdentity identity,
  ) async {
    final session = _registry.forAccount(accountId);
    var created = (await session.mailService.createIdentity(identity))
        .copyWith(accountId: accountId);
    if (created.isDefault) {
      await listIdentities(accountId, refresh: true);
      created = session.identities!.firstWhere((item) => item.id == created.id);
    } else {
      final items = session.identities ?? <MailIdentity>[];
      session.identities = [...items, created];
    }
    _notify();
    return created;
  }

  Future<MailIdentity> updateIdentity(
    String accountId,
    MailIdentity identity,
  ) async {
    final session = _registry.forAccount(accountId);
    var updated = (await session.mailService.updateIdentity(identity))
        .copyWith(accountId: accountId);
    if (updated.isDefault) {
      await listIdentities(accountId, refresh: true);
      updated = session.identities!.firstWhere((item) => item.id == updated.id);
    } else if (session.identities != null) {
      session.identities = [
        for (final item in session.identities!)
          if (item.id == updated.id) updated else item,
      ];
    }
    _notify();
    return updated;
  }

  Future<void> deleteIdentity(String accountId, String identityId) async {
    final session = _registry.forAccount(accountId);
    await session.mailService.deleteIdentity(identityId);
    session.identities?.removeWhere((item) => item.id == identityId);
    _notify();
  }

  Future<void> setSignature(String accountId, String? signature) async {
    final session = _registry.forAccount(accountId);
    final trimmed = signature?.trim();
    final normalized = trimmed == null || trimmed.isEmpty ? null : trimmed;
    await session.mailService.updateSignature(normalized);
    session.account = session.account.copyWith(signature: normalized);
    _notify();
  }

  /// One-time migration for pre-cutover installs: if the backend has no
  /// signature yet but the old per-device SharedPreferences store does,
  /// push it once so it starts syncing. Best-effort — a failure here must
  /// never affect login.
  Future<void> migrateLegacy(AccountSession session) async {
    if (session.account.signature != null) return;
    try {
      final legacy = await SignatureStore.load(session.account.email);
      if (legacy.trim().isEmpty) return;
      await session.mailService.updateSignature(legacy);
      session.account = session.account.copyWith(signature: legacy);
      await SignatureStore.save(session.account.email, '');
      _notify();
    } catch (_) {
      // Best-effort; the legacy value stays local and compose still finds
      // it via SignatureStore until the next successful login.
    }
  }
}
