import 'package:flutter/material.dart';

import '../../models/mail_label.dart';
import '../../services/api_exception.dart';
import '../../services/local_mail_flags_store.dart';
import 'account_session.dart';
import 'repository_context.dart';
import '../../l10n/l10n.dart';

/// Backend-owned labels with an offline queue: label CRUD per account and
/// assigning labels to mails, optimistic with rollback.
class LabelModule {
  LabelModule(this._ctx);

  final RepositoryContext _ctx;

  /// Label colours travel as signed 32-bit ARGB on the wire.
  static int signedArgb(int color) =>
      color >= 0x80000000 ? color - 0x100000000 : color;

  static int unsignedArgb(int color) => color & 0xFFFFFFFF;

  static String _canonicalName(String name) =>
      name.trim().replaceAll('İ', 'i').toLowerCase();

  void _assertLabelNameIsFree(
    AccountSession session,
    String name, {
    String? selfId,
  }) {
    final canonical = _canonicalName(name);
    if (canonical.isEmpty) throw ArgumentError(l10nNow.labelNameCantBeEmpty);
    if (session.labels.any(
      (l) => l.id != selfId && _canonicalName(l.name) == canonical,
    )) {
      throw ArgumentError(l10nNow.aLabelWithThisName);
    }
  }

  /// Mirrors backend-confirmed label state into the local cache so labels
  /// still show while offline. Never the source of truth — see [_loadLabels].
  Future<void> persist(AccountSession session) async {
    final store = session.flagsStore;
    if (store == null) return;
    await store.writeLabelDefs([
      for (final l in session.labels)
        {'id': l.id, 'name': l.name, 'color': l.color.toARGB32()},
    ]);
    await store.writeLabelMap(session.labelMap);
  }

  Future<void> _queueLabels(
    AccountSession session,
    List<String> mailIds,
    Iterable<String> labelIds,
    String operation,
  ) async {
    _ctx.markOffline(session);
    final store = session.flagsStore;
    if (store == null) return;
    for (final mailId in mailIds) {
      for (final labelId in labelIds) {
        await store.queueMutation(mailId, operation, folderId: labelId);
      }
    }
  }

  Future<void> _clearQueuedLabels(
    AccountSession session,
    List<String> mailIds,
    Iterable<String> labelIds,
  ) async {
    final store = session.flagsStore;
    if (store == null) return;
    for (final mailId in mailIds) {
      for (final labelId in labelIds) {
        await store.clearQueuedMutation(
          mailId,
          mutationCategoryFor('label_add', labelId),
        );
      }
    }
  }

  void restamp(AccountSession session, Iterable<String> ids) =>
      _ctx.replaceMany(
        session,
        ids.toList(),
        (e) => e.copyWith(labelIds: session.labelMap[e.id] ?? const []),
      );

  /// Labels from every account in scope — the unified view unions them
  /// (dedup by id; account-local ids never collide in practice).
  List<MailLabel> getLabels() {
    final seen = <String>{};
    final result = <MailLabel>[];
    for (final session in _ctx.registry.scoped) {
      for (final label in session.labels) {
        if (seen.add(label.id)) result.add(label);
      }
    }
    return List.unmodifiable(result);
  }

  List<MailLabel> getLabelsForAccount(String accountId) => List.unmodifiable(
    _ctx.registry.sessions[accountId]?.labels ?? const <MailLabel>[],
  );

  Future<MailLabel> createLabel({
    required String name,
    required Color color,
    String? accountId,
  }) async {
    final session = accountId == null
        ? _ctx.registry.primary
        : _ctx.registry.forAccount(accountId);
    _assertLabelNameIsFree(session, name);
    final trimmed = name.trim();
    Map<String, dynamic> created;
    try {
      created = await session.mailService.createLabel(
        trimmed,
        signedArgb(color.toARGB32()),
      );
    } on ApiException catch (e) {
      if (e.code == 'label_name_taken') {
        throw ArgumentError(l10nNow.aLabelWithThisName);
      }
      rethrow;
    }
    final label = MailLabel(
      id: created['id'] as String,
      name: created['name'] as String,
      color: Color(unsignedArgb(created['color'] as int)),
    );
    session.labels = [...session.labels, label];
    await persist(session);
    _ctx.notify();
    return label;
  }

  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) async {
    final session = _ctx.registry.forLabel(id);
    if (session == null) return;
    final index = session.labels.indexWhere((l) => l.id == id);
    if (index < 0) return;
    _assertLabelNameIsFree(session, name, selfId: id);
    final trimmed = name.trim();
    try {
      await session.mailService.updateLabel(
        id,
        trimmed,
        signedArgb(color.toARGB32()),
      );
    } on ApiException catch (e) {
      if (e.code == 'label_name_taken') {
        throw ArgumentError(l10nNow.aLabelWithThisName);
      }
      rethrow;
    }
    session.labels = [...session.labels]
      ..[index] = MailLabel(id: id, name: trimmed, color: color);
    await persist(session);
    _ctx.notify();
  }

  Future<void> deleteLabel(String labelId) async {
    final session = _ctx.registry.forLabel(labelId);
    if (session == null) return;
    try {
      await session.mailService.deleteLabel(labelId);
    } catch (_) {
      // Never desync: a failed server delete leaves local state untouched.
      return;
    }
    session.labels = session.labels.where((l) => l.id != labelId).toList();
    final touched = [
      for (final e in session.labelMap.entries)
        if (e.value.contains(labelId)) e.key,
    ];
    for (final id in touched) {
      session.labelMap[id] = session.labelMap[id]!
          .where((l) => l != labelId)
          .toList();
    }
    await persist(session);
    restamp(session, touched);
    _ctx.notify();
  }

  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _changeEmailLabels(emailIds, labelIds, add: true);

  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _changeEmailLabels(emailIds, labelIds, add: false);

  Future<void> _changeEmailLabels(
    List<String> emailIds,
    List<String> labelIds, {
    required bool add,
  }) async {
    Object? firstError;
    for (final entry in _ctx.registry.groupByOwner(emailIds).entries) {
      final session = entry.key;
      final ownedLabelIds = {
        for (final label in session.labels)
          if (labelIds.contains(label.id)) label.id,
      };
      if (ownedLabelIds.isEmpty) continue;
      final previous = {
        for (final id in entry.value)
          id: List<String>.of(session.labelMap[id] ?? const []),
      };
      for (final id in entry.value) {
        final current = session.labelMap[id] ?? const <String>[];
        session.labelMap[id] = add
            ? [
                ...current,
                ...ownedLabelIds.where((label) => !current.contains(label)),
              ]
            : current.where((label) => !ownedLabelIds.contains(label)).toList();
      }
      restamp(session, entry.value);
      _ctx.notify();
      try {
        try {
          if (add) {
            await session.mailService.assignLabels(
              entry.value,
              ownedLabelIds.toList(),
            );
          } else {
            await session.mailService.unassignLabels(
              entry.value,
              ownedLabelIds.toList(),
            );
          }
          await _clearQueuedLabels(session, entry.value, ownedLabelIds);
        } catch (error) {
          if (!_ctx.isOfflineFailure(error)) rethrow;
          await _queueLabels(
            session,
            entry.value,
            ownedLabelIds,
            add ? 'label_add' : 'label_remove',
          );
        }
        await persist(session);
      } catch (error) {
        for (final previousEntry in previous.entries) {
          session.labelMap[previousEntry.key] = previousEntry.value;
        }
        restamp(session, entry.value);
        _ctx.notify();
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }
}
