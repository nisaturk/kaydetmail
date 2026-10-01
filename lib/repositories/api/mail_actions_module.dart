import 'dart:async';
import 'dart:convert';

import '../../models/email.dart';
import '../../models/mail_folder.dart';
import '../../models/manual_contact.dart';
import '../../services/api_exception.dart';
import '../../services/api_mail_service.dart';
import '../../services/local_mail_flags_store.dart';
import 'account_session.dart';
import 'mail_buckets.dart';
import 'repository_context.dart';

/// Mail state changes — read/unread, star, pin, snooze, archive/trash/move,
/// permanent delete, replied/forwarded — applied optimistically to the
/// in-memory buckets, confirmed against the backend per account, rolled back
/// when rejected and queued for replay while offline.
class MailActionsModule {
  MailActionsModule(this._ctx, this._buckets);

  final RepositoryContext _ctx;
  final MailBuckets _buckets;

  /// Applies a bulk action immediately in the local cache, then reconciles
  /// per-item results with the server. Transport failures keep the optimistic
  /// state and persist a mutation for replay; rejected items restore their
  /// previous cache locations. Permanent `delete` is handled separately.
  Future<List<BulkActionResult>> bulkAndApplyOrQueue(
    AccountSession session,
    String operation,
    List<String> ids,
    void Function(List<String> succeededIds) apply, {
    String? folderId,
  }) async {
    if (ids.isEmpty) return const [];
    final snapshots = _buckets.snapshotMailLocations(session, ids);
    apply(ids);
    _ctx.notify();
    List<BulkActionResult> results;
    try {
      results = await session.mailService.bulkAction(
        operation,
        ids,
        folderId: folderId,
      );
    } catch (error) {
      if (!_ctx.isOfflineFailure(error)) {
        _buckets.restoreMailLocations(session, snapshots);
        _ctx.notify();
        rethrow;
      }
      results = [
        for (final id in ids)
          BulkActionResult(
            mailId: id,
            success: false,
            code: error is ApiException ? error.code : 'network_unavailable',
            retryable: true,
          ),
      ];
    }
    final rejected = <String>[];
    final store = session.flagsStore;
    final category = mutationCategoryFor(operation, folderId);
    Object? queueError;
    for (final result in results) {
      if (result.success) {
        _buckets.replaceMany(
          session,
          [result.mailId],
          (mail) => mail.copyWith(
            reconciliationPending: result.reconciliationPending,
          ),
        );
        await store?.clearQueuedMutation(result.mailId, category);
      } else if (result.canRetry) {
        if (result.code == 'network_unavailable' ||
            result.code == 'request_timeout') {
          _ctx.markOffline(session);
        }
        try {
          await store?.queueMutation(
            result.mailId,
            operation,
            folderId: folderId,
            originFolderId: _originFolderId(session, snapshots[result.mailId]),
          );
        } catch (error) {
          queueError ??= error;
          rejected.add(result.mailId);
        }
        if (result.code == 'mail_reconciliation_pending') {
          _buckets.replaceMany(session, [
            result.mailId,
          ], (mail) => mail.copyWith(reconciliationPending: true));
        }
      } else {
        rejected.add(result.mailId);
      }
    }
    if (rejected.isNotEmpty) {
      _buckets.restoreMailLocations(
        session,
        _buckets.selectMailLocations(snapshots, rejected),
      );
    }
    _ctx.notify();
    if (queueError != null) throw queueError;
    _ctx.refreshCounts(session);
    return results;
  }

  void throwForFailedBulkResults(
    Iterable<Iterable<BulkActionResult>> accountResults,
  ) {
    final failure = accountResults
        .expand((results) => results)
        .where(
          (result) =>
              !result.success &&
              (!result.canRetry ||
                  result.code == 'mail_reconciliation_pending'),
        )
        .firstOrNull;
    if (failure != null) {
      throw ApiException(
        status: 0,
        code: failure.code ?? 'mail_operation_failed',
      );
    }
  }

  String? _originFolderId(
    AccountSession session,
    MailLocationSnapshot? snapshot,
  ) {
    if (snapshot == null) return null;
    return snapshot.customFolders.keys.firstOrNull ??
        session.folderIds[snapshot.folders.keys.firstOrNull];
  }

  /// Replays queued mail, pin/snooze/label and manual contact mutations.
  /// Transport failures remain queued for the next reconnect. Server
  /// rejections are dropped and surfaced through [offlineMutationConflicts];
  /// backend-owned state is re-read to replace rejected optimistic changes.
  /// Mail changes in the same category and contact changes for the same id
  /// collapse at queue time (see `LocalMailFlagsStore.queueMutation`).
  Future<void> replayQueuedMutations(AccountSession session) async {
    final active = session.mutationReplay;
    if (active != null) return active;
    final replay = _replayQueuedMutations(session);
    session.mutationReplay = replay;
    try {
      await replay;
    } finally {
      if (identical(session.mutationReplay, replay)) {
        session.mutationReplay = null;
      }
    }
  }

  Future<void> _replayQueuedMutations(AccountSession session) async {
    final store = session.flagsStore;
    if (store == null) return;
    final all = await store.readQueuedMutations();
    if (all.isEmpty) return;
    final contacts = [
      for (final m in all)
        if (_contactOperations.contains(m.operation)) m,
    ];
    if (contacts.isNotEmpty) {
      await _replayManualContacts(session, store, contacts);
    }
    final queued = [
      for (final m in all)
        if (!_appStateOperations.contains(m.operation) &&
            !_contactOperations.contains(m.operation))
          m,
    ];
    final appState = [
      for (final m in all)
        if (_appStateOperations.contains(m.operation)) m,
    ];
    if (queued.isEmpty) {
      if (appState.isNotEmpty) await _replayAppState(session, store, appState);
      return;
    }
    final byOp = <(String, String?), List<QueuedMutation>>{};
    for (final mutation in queued) {
      byOp
          .putIfAbsent((mutation.operation, mutation.folderId), () => [])
          .add(mutation);
    }
    var changed = false;
    for (final entry in byOp.entries) {
      final (operation, folderId) = entry.key;
      final ids = [for (final m in entry.value) m.mailId];
      final category = mutationCategoryFor(operation, folderId);
      List<BulkActionResult> results;
      try {
        results = await session.mailService.bulkAction(
          operation,
          ids,
          folderId: folderId,
        );
      } catch (error) {
        if (error is! ApiException ||
            error.isTransient ||
            error.category == ApiErrorCategory.authentication ||
            error.code == 'mail_account_needs_reauthentication') {
          continue;
        }
        results = [
          for (final id in ids)
            BulkActionResult(mailId: id, success: false, code: error.code),
        ];
      }
      final restored = <String>[];
      final rejected = <String>[];
      for (final r in results) {
        if (r.success) {
          await store.clearQueuedMutation(r.mailId, category);
          _buckets.replaceMany(
            session,
            [r.mailId],
            (mail) =>
                mail.copyWith(reconciliationPending: r.reconciliationPending),
          );
          changed = true;
          if (operation == 'restore' || operation == 'move') {
            restored.add(r.mailId);
          }
        } else if (!r.canRetry) {
          await store.clearQueuedMutation(r.mailId, category);
          session.mutationConflicts.add(r.mailId);
          if (r.code == 'mail_not_found') {
            _buckets.removeMany(session, [r.mailId]);
          } else {
            rejected.add(r.mailId);
          }
          changed = true;
        }
      }
      if (restored.isNotEmpty) await _fileRestored(session, restored);
      if (rejected.isNotEmpty) await _fileRestored(session, rejected);
    }
    if (changed) _ctx.notify();
    if (appState.isNotEmpty) await _replayAppState(session, store, appState);
  }

  static const _appStateOperations = {
    'pin',
    'unpin',
    'snooze',
    'unsnooze',
    'label_add',
    'label_remove',
  };

  /// Replays queued pin/snooze/label changes. A still-unreachable backend
  /// leaves them queued; a server rejection (e.g. pin cap reached on another
  /// device) drops the mutation and surfaces it via [offlineMutationConflicts].
  /// Once nothing of that kind is left queued, pins, snoozes and label
  /// assignments are re-read from the backend so the local cache matches the
  /// authoritative state.
  Future<void> _replayAppState(
    AccountSession session,
    LocalMailFlagsStore store,
    List<QueuedMutation> queued,
  ) async {
    var stillQueued = false;
    final groups = <(String, String?), List<String>>{};
    for (final m in queued) {
      final key = m.operation.contains('snooze')
          ? (m.operation, '${m.mailId}\u0000${m.folderId ?? ''}')
          : (m.operation, m.folderId);
      groups.putIfAbsent(key, () => []).add(m.mailId);
    }
    for (final MapEntry(key: (operation, argument), value: ids)
        in groups.entries) {
      Future<void> drop(Iterable<String> mailIds) async {
        for (final id in mailIds) {
          await store.clearQueuedMutation(
            id,
            mutationCategoryFor(
              operation,
              operation.startsWith('label') ? argument : null,
            ),
          );
          session.mutationConflicts.add(id);
        }
      }

      try {
        switch (operation) {
          case 'pin' || 'unpin':
            final results = await session.mailService.setPinned(
              ids,
              operation == 'pin',
            );
            for (final r in results) {
              if (r.success) {
                await store.clearQueuedMutation(r.mailId, 'pin_state');
              } else {
                await drop([r.mailId]);
              }
            }
          case 'snooze':
            final until = DateTime.parse(argument!.split('\u0000').last);
            await session.mailService.setSnooze(ids.single, until);
            await store.clearQueuedMutation(ids.single, 'snooze_state');
          case 'unsnooze':
            await session.mailService.clearSnooze(ids.single);
            await store.clearQueuedMutation(ids.single, 'snooze_state');
          case 'label_add' || 'label_remove':
            operation == 'label_add'
                ? await session.mailService.assignLabels(ids, [argument!])
                : await session.mailService.unassignLabels(ids, [argument!]);
            for (final id in ids) {
              await store.clearQueuedMutation(
                id,
                mutationCategoryFor(operation, argument),
              );
            }
        }
      } catch (error) {
        if (_ctx.isOfflineFailure(error)) {
          stillQueued = true;
        } else if (error is ApiException) {
          await drop(ids);
        } else {
          stillQueued = true;
        }
      }
    }
    if (stillQueued) return;
    session.pinnedIds = await _ctx.loadPinnedIds(session, store);
    session.snoozedUntil = await _ctx.loadSnoozedUntil(session, store);
    try {
      session.labelMap = await session.mailService.getLabelAssignments();
      await store.writeLabelMap(session.labelMap);
    } catch (_) {}
    _ctx.recomputeSnoozeDeadline();
    _buckets.restampFlags(session);
    _ctx.restampLabels(session, [
      for (final list in session.emails.values)
        for (final e in list) e.id,
    ]);
    _ctx.notify();
  }

  static const _contactOperations = {
    'contact_create',
    'contact_update',
    'contact_delete',
  };

  Future<void> _replayManualContacts(
    AccountSession session,
    LocalMailFlagsStore store,
    List<QueuedMutation> queued,
  ) async {
    var stillQueued = false;
    var createdContact = false;
    for (final m in queued) {
      final payload = m.folderId == null
          ? null
          : jsonDecode(m.folderId!) as Map<String, dynamic>;
      try {
        switch (m.operation) {
          case 'contact_create':
            final created = await session.mailService.createContact(
              payload!['email'] as String,
              payload['displayName'] as String?,
            );
            session.manualContacts = [
              for (final c in session.manualContacts)
                c.id == m.mailId
                    ? ManualContact(
                        id: created['id'] as String,
                        accountId: c.accountId,
                        email: c.email,
                        displayName: c.displayName,
                      )
                    : c,
            ];
            createdContact = true;
          case 'contact_update':
            await session.mailService.updateContact(
              m.mailId,
              payload!['email'] as String,
              payload['displayName'] as String?,
            );
          case 'contact_delete':
            await session.mailService.deleteContact(m.mailId);
        }
        await store.clearQueuedMutation(m.mailId, 'contact');
      } catch (error) {
        if (error is ApiException && !_ctx.isOfflineFailure(error)) {
          await store.clearQueuedMutation(m.mailId, 'contact');
          session.mutationConflicts.add(m.mailId);
        } else {
          stillQueued = true;
        }
      }
    }
    if (createdContact || stillQueued) await _ctx.persistContacts(session);
    if (stillQueued) return;
    await _ctx.loadManualContacts(session, store);
    _ctx.notify();
  }

  Future<void> moveToTrash(List<String> ids) async {
    final results = await Future.wait(
      _ctx.registry
          .groupByOwner(ids)
          .entries
          .map(
            (entry) => bulkAndApplyOrQueue(
              entry.key,
              'trash',
              entry.value,
              (succeeded) =>
                  _buckets.moveMany(entry.key, succeeded, MailFolder.trash),
            ),
          ),
    );
    throwForFailedBulkResults(results);
  }

  /// Expunge is irreversible: retain cached messages until server confirmation.
  Future<void> deletePermanently(List<String> ids) async {
    final failures = <String>[];
    await Future.wait(
      _ctx.registry.groupByOwner(ids).entries.map((entry) async {
        final session = entry.key;
        final results = await session.mailService.bulkAction(
          'delete',
          entry.value,
        );
        final successfulIds = results
            .where((result) => result.success)
            .map((result) => result.mailId)
            .toList();
        if (successfulIds.isNotEmpty) {
          _buckets.removeMany(session, successfulIds);
          _ctx.notify();
        }
        for (final result in results) {
          if (result.code == 'mail_reconciliation_pending') {
            _buckets.replaceMany(session, [
              result.mailId,
            ], (mail) => mail.copyWith(reconciliationPending: true));
          }
        }
        failures.addAll([
          for (final result in results)
            if (!result.success) result.code ?? 'mail_operation_failed',
        ]);
        _ctx.refreshCounts(session);
      }),
    );
    if (failures.isNotEmpty) {
      throw ApiException(status: 0, code: failures.first);
    }
  }

  /// Server-backed Trash/Spam restores use the recorded server origin. An
  /// outstanding offline move instead has a persisted local origin, so undo
  /// reduces to an explicit target and never restores an unchanged source.
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async {
    if (ids.isEmpty) return;
    for (final entry in _ctx.registry.groupByOwner(ids).entries) {
      final session = entry.key;
      final folderId = session.folderIds[folder];
      if (folderId == null) {
        throw ArgumentError('Unknown target folder for this account: $folder');
      }
      final idsForSession = entry.value;
      final restoring = _buckets.idsInTrashOrSpam(session, idsForSession);
      if (restoring.isNotEmpty) {
        final queued =
            await session.flagsStore?.readQueuedMutations() ??
            const <QueuedMutation>[];
        final byId = {
          for (final mutation in queued)
            if (mutationCategoryFor(mutation.operation, mutation.folderId) ==
                'location')
              mutation.mailId: mutation,
        };
        final groups = <String?, List<String>>{};
        for (final id in restoring) {
          final previous = byId[id];
          final target =
              previous != null &&
                  const {
                    'trash',
                    'spam',
                    'archive',
                    'move',
                  }.contains(previous.operation)
              ? previous.originFolderId
              : null;
          groups.putIfAbsent(target, () => []).add(id);
        }
        for (final group in groups.entries) {
          final targetId = group.key;
          final targetFolder = targetId == null
              ? MailFolder.inbox
              : session.resolveFolder(targetId);
          final results = await bulkAndApplyOrQueue(
            session,
            targetId == null ? 'restore' : 'move',
            group.value,
            (affected) {
              if (targetId == null ||
                  session.folderTypeById.containsKey(targetId)) {
                _buckets.moveMany(session, affected, targetFolder);
              } else {
                final moved = [
                  for (final id in affected)
                    if (session.findLoaded(id) case final mail?)
                      mail.copyWith(folder: targetFolder),
                ];
                _buckets.removeMany(session, affected);
                session.customFolderEmails
                    .putIfAbsent(targetId, () => <Email>[])
                    .insertAll(0, moved);
              }
            },
            folderId: targetId,
          );
          final restored = [
            for (final result in results)
              if (result.success) result.mailId,
          ];
          if (targetId == null) await _fileRestored(session, restored);
          throwForFailedBulkResults([results]);
        }
      }

      final rest = idsForSession
          .where((id) => !restoring.contains(id))
          .toList();
      if (rest.isNotEmpty) {
        final results = await bulkAndApplyOrQueue(
          session,
          folder == MailFolder.archive ? 'archive' : 'move',
          rest,
          (succeeded) => _buckets.moveMany(session, succeeded, folder),
          folderId: folder == MailFolder.archive ? null : folderId,
        );
        throwForFailedBulkResults([results]);
      }
    }
  }

  /// `restore` sends each mail back to the folder it was trashed/spammed
  /// from, which only the server tracks — the target a caller passes to
  /// [moveToFolder] says nothing about where it went (a restored draft goes
  /// back to Drafts, not Inbox). Asks the server where each mail landed and
  /// files it there, retaining raw custom folder ids instead of displaying an
  /// untracked restored message in Inbox.
  Future<void> _fileRestored(AccountSession session, List<String> ids) async {
    if (ids.isEmpty) return;
    final details = await Future.wait(
      ids.map((id) async {
        String? landedFolderId;
        try {
          final detail = await session.mailService.getMail(
            id,
            resolveFolder: (folderId) {
              landedFolderId = folderId;
              return session.resolveFolder(folderId);
            },
          );
          return (detail, landedFolderId);
        } catch (_) {
          return null;
        }
      }),
    );
    for (final resolved in details) {
      if (resolved == null) continue;
      final (detail, rawFolderId) = resolved;
      _buckets.removeMany(session, [detail.id]);
      final list =
          rawFolderId != null &&
              !session.folderTypeById.containsKey(rawFolderId)
          ? session.customFolderEmails.putIfAbsent(rawFolderId, () => <Email>[])
          : session.emails.putIfAbsent(detail.folder, () => <Email>[]);
      list.insert(0, session.stampLocalFlags(detail));
    }
    _ctx.notify();
  }

  Future<void> markAsRead(List<String> ids) async {
    final results = await Future.wait(
      _ctx.registry
          .groupByOwner(ids)
          .entries
          .map(
            (entry) => bulkAndApplyOrQueue(
              entry.key,
              'read',
              entry.value,
              (affected) => _buckets.replaceMany(
                entry.key,
                affected,
                (mail) => mail.copyWith(isRead: true),
              ),
            ),
          ),
    );
    throwForFailedBulkResults(results);
  }

  Future<void> markAsUnread(List<String> ids) async {
    final results = await Future.wait(
      _ctx.registry
          .groupByOwner(ids)
          .entries
          .map(
            (entry) => bulkAndApplyOrQueue(
              entry.key,
              'unread',
              entry.value,
              (affected) => _buckets.replaceMany(
                entry.key,
                affected,
                (mail) => mail.copyWith(isRead: false),
              ),
            ),
          ),
    );
    throwForFailedBulkResults(results);
  }

  List<String> get offlineMutationConflicts => [
    for (final session in _ctx.registry.scoped) ...session.mutationConflicts,
  ];

  void dismissMutationConflict(String id) {
    for (final session in _ctx.registry.sessions.values) {
      if (session.mutationConflicts.remove(id)) {
        _ctx.notify();
        return;
      }
    }
  }

  /// Updates pin state optimistically; the server remains authoritative and
  /// rejected changes are rolled back before the error is returned.
  Future<void> setPinned(List<String> ids, bool pinned) async {
    if (ids.isEmpty) return;
    final accountResults = <List<BulkActionResult>>[];
    await Future.wait(
      _ctx.registry.groupByOwner(ids).entries.map((entry) async {
        final session = entry.key;
        final affected = entry.value;
        final previous = {
          for (final id in affected) id: session.pinnedIds.contains(id),
        };
        if (pinned) {
          session.pinnedIds.addAll(affected);
        } else {
          session.pinnedIds.removeAll(affected);
        }
        _buckets.replaceMany(
          session,
          affected,
          (mail) => mail.copyWith(isPinned: pinned),
        );
        _ctx.notify();
        List<BulkActionResult> results;
        try {
          results = await session.mailService.setPinned(affected, pinned);
        } catch (error) {
          if (!_ctx.isOfflineFailure(error)) {
            _restorePinnedState(session, previous);
            _ctx.notify();
            rethrow;
          }
          _ctx.markOffline(session);
          try {
            for (final id in affected) {
              await session.flagsStore?.queueMutation(
                id,
                pinned ? 'pin' : 'unpin',
              );
            }
          } catch (_) {
            _restorePinnedState(session, previous);
            _ctx.notify();
            rethrow;
          }
          await session.flagsStore?.writePinned(session.pinnedIds);
          return;
        }
        accountResults.add(results);
        final successful = results
            .where((result) => result.success)
            .map((result) => result.mailId)
            .toSet();
        final rejected = {
          for (final id in affected)
            if (!successful.contains(id)) id: previous[id]!,
        };
        if (rejected.isNotEmpty) {
          _restorePinnedState(session, rejected);
          _ctx.notify();
        }
        for (final id in successful) {
          await session.flagsStore?.clearQueuedMutation(id, 'pin_state');
        }
        await session.flagsStore?.writePinned(session.pinnedIds);
      }),
    );
    throwForFailedBulkResults(accountResults);
  }

  void _restorePinnedState(AccountSession session, Map<String, bool> previous) {
    for (final entry in previous.entries) {
      if (entry.value) {
        session.pinnedIds.add(entry.key);
      } else {
        session.pinnedIds.remove(entry.key);
      }
    }
    _buckets.replaceMany(
      session,
      previous.keys,
      (mail) => mail.copyWith(isPinned: previous[mail.id] ?? false),
    );
  }

  Future<void> setStarred(List<String> ids, bool starred) async {
    final results = await Future.wait(
      _ctx.registry.groupByOwner(ids).entries.map((entry) {
        final session = entry.key;
        return bulkAndApplyOrQueue(
          session,
          starred ? 'star' : 'unstar',
          entry.value,
          (affected) {
            starred
                ? session.starredIds.addAll(affected)
                : session.starredIds.removeAll(affected);
            _buckets.replaceMany(
              session,
              affected,
              (mail) => mail.copyWith(isStarred: starred),
            );
          },
        );
      }),
    );
    throwForFailedBulkResults(results);
  }

  /// Records a reply successfully sent from KaydetMail. The "replied" flag
  /// itself is local-only (see [LocalMailFlagsStore]); the resulting read
  /// state goes through the real `read` action instead of being faked
  /// locally.
  Future<void> markAsReplied(List<String> ids) async {
    if (ids.isEmpty) return;
    await markAsRead(ids);
    for (final entry in _ctx.registry.groupByOwner(ids).entries) {
      final session = entry.key;
      final store = session.flagsStore;
      if (store == null) continue;
      session.repliedFromKaydetMailIds.addAll(entry.value);
      for (final id in entry.value) {
        final threadId = session.findLoaded(id)?.threadId;
        if (threadId != null && threadId.isNotEmpty) {
          session.repliedFromKaydetMailThreadIds.add(threadId);
        }
      }
      await Future.wait([
        store.writeRepliedFromKaydetMail(session.repliedFromKaydetMailIds),
        store.writeRepliedFromKaydetMailThreads(
          session.repliedFromKaydetMailThreadIds,
        ),
      ]);
      _buckets.restampFlags(session);
    }
    _ctx.notify();
  }

  /// Snoozing changes the virtual folder membership, so apply it immediately
  /// and reconcile each item with the backend response. Offline writes stay
  /// queued; rejected online writes restore their previous deadlines.
  Future<void> setSnoozed(List<String> ids, DateTime? until) async {
    if (ids.isEmpty) return;
    final errors = <Object>[];
    await Future.wait(
      _ctx.registry.groupByOwner(ids).entries.map((entry) async {
        final session = entry.key;
        final store = session.flagsStore;
        final previous = {
          for (final id in entry.value) id: session.snoozedUntil[id],
        };
        if (until == null) {
          session.snoozedUntil.removeWhere((id, _) => entry.value.contains(id));
        } else {
          final deadline = until.toUtc().millisecondsSinceEpoch;
          for (final id in entry.value) {
            session.snoozedUntil[id] = deadline;
          }
        }
        _ctx.recomputeSnoozeDeadline();
        _ctx.touch();
        _ctx.notify();

        final rejected = <String>{};
        await Future.wait(
          entry.value.map((id) async {
            try {
              if (until == null) {
                await session.mailService.clearSnooze(id);
              } else {
                await session.mailService.setSnooze(id, until);
              }
              await store?.clearQueuedMutation(id, 'snooze_state');
            } catch (error) {
              if (_ctx.isOfflineFailure(error)) {
                _ctx.markOffline(session);
                try {
                  await store?.queueMutation(
                    id,
                    until == null ? 'unsnooze' : 'snooze',
                    folderId: until?.toUtc().toIso8601String(),
                  );
                  return;
                } catch (queueError) {
                  errors.add(queueError);
                }
              } else {
                errors.add(error);
              }
              rejected.add(id);
            }
          }),
        );
        for (final id in rejected) {
          final deadline = previous[id];
          if (deadline == null) {
            session.snoozedUntil.remove(id);
          } else {
            session.snoozedUntil[id] = deadline;
          }
        }
        await store?.writeSnoozed(session.snoozedUntil);
        if (rejected.isNotEmpty) {
          _ctx.recomputeSnoozeDeadline();
          _ctx.touch();
          _ctx.notify();
        }
      }),
    );
    if (errors.isNotEmpty) throw errors.first;
  }

  DateTime? snoozedUntilOf(String mailId) {
    for (final session in _ctx.registry.scoped) {
      final until = session.activeSnoozeDeadline(mailId);
      if (until != null) return until;
    }
    return null;
  }

  /// Records a forward successfully sent from KaydetMail — same split as
  /// [markAsReplied]: "forwarded" is local-only, the resulting read state
  /// goes through the real `read` action.
  Future<void> markAsForwarded(List<String> ids) async {
    if (ids.isEmpty) return;
    await markAsRead(ids);
    for (final entry in _ctx.registry.groupByOwner(ids).entries) {
      final session = entry.key;
      final store = session.flagsStore;
      if (store == null) continue;
      session.forwardedFromKaydetMailIds.addAll(entry.value);
      for (final id in entry.value) {
        final threadId = session.findLoaded(id)?.threadId;
        if (threadId != null && threadId.isNotEmpty) {
          session.forwardedFromKaydetMailThreadIds.add(threadId);
        }
      }
      await Future.wait([
        store.writeForwardedFromKaydetMail(session.forwardedFromKaydetMailIds),
        store.writeForwardedFromKaydetMailThreads(
          session.forwardedFromKaydetMailThreadIds,
        ),
      ]);
      _buckets.restampFlags(session);
    }
    _ctx.notify();
  }
}
