import 'package:flutter/foundation.dart';

import '../models/mail_custom_folder.dart';
import '../services/app_preferences_store.dart';

/// User-defined custom folder order, persisted per account in
/// [AppPreferencesStore]. Each account keeps a preorder list of folder ids;
/// [buildCustomFolderTree] applies it among siblings only, so the tree shape
/// always comes from the server.
class CustomFolderOrderController extends ChangeNotifier {
  CustomFolderOrderController._();

  static final instance = CustomFolderOrderController._();

  final Map<String, List<String>> _orders = {};
  final Map<String, Future<void>> _loads = {};

  /// Loaded orders keyed by account id; pass to `orderByAccount`.
  Map<String, List<String>> get orders => Map.unmodifiable(_orders);

  /// Loads persisted orders for the accounts present in [folders] and
  /// reconciles each with the live folder set: removed ids are dropped and
  /// new folders are appended alphabetically. Accounts with no folders in
  /// [folders] are left untouched, so a not-yet-loaded folder list (offline
  /// cold start) never wipes a saved order.
  Future<void> sync(Iterable<MailCustomFolder> folders) async {
    final byAccount = <String, List<MailCustomFolder>>{};
    for (final folder in folders) {
      byAccount.putIfAbsent(folder.accountId, () => []).add(folder);
    }
    await Future.wait(byAccount.keys.map(_ensureLoaded));

    var changed = false;
    for (final MapEntry(key: accountId, value: accountFolders)
        in byAccount.entries) {
      final current = _orders[accountId] ?? const <String>[];
      final reconciled = reconcileCustomFolderOrder(accountFolders, current);
      if (listEquals(current, reconciled)) continue;
      _orders[accountId] = reconciled;
      changed = true;
      await _save(accountId, reconciled);
    }
    if (changed) notifyListeners();
  }

  /// Moves [folderId] by [offset] among its siblings in [accountFolders]
  /// (all from one account). Returns false when the move is out of range.
  Future<bool> move(
    List<MailCustomFolder> accountFolders,
    String folderId,
    int offset,
  ) async {
    if (accountFolders.isEmpty) return false;
    final accountId = accountFolders.first.accountId;
    await _ensureLoaded(accountId);
    final base = reconcileCustomFolderOrder(
      accountFolders,
      _orders[accountId] ?? const [],
    );
    final next = moveCustomFolderAmongSiblings(
      accountFolders,
      base,
      folderId,
      offset,
    );
    if (next == null) return false;
    _orders[accountId] = next;
    notifyListeners();
    await _save(accountId, next);
    return true;
  }

  Future<void> _ensureLoaded(String accountId) =>
      _loads[accountId] ??= AppPreferencesStore.loadCustomFolderOrder(
        accountId,
      ).then((order) => _orders.putIfAbsent(accountId, () => List.of(order)));

  Future<void> _save(String accountId, List<String> order) async {
    try {
      await AppPreferencesStore.saveCustomFolderOrder(accountId, order);
    } catch (_) {
      // Best-effort: the in-memory order still applies for this session.
    }
  }

  /// Drops in-memory state, as after an app restart; persisted orders stay.
  @visibleForTesting
  static void resetForTest() {
    instance._orders.clear();
    instance._loads.clear();
  }
}
