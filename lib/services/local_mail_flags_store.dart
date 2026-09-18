import 'package:shared_preferences/shared_preferences.dart';

/// Persists mail flags the backend has no concept of.
///
/// Pinning is a purely client-side favoriting feature — the API never sees
/// it. "Replied"/"forwarded" mark the moment the user opened the reply/
/// forward compose screen, not a delivered server-side state, and no mail
/// response in the API schema carries an equivalent field. Both are kept
/// locally, scoped per account so switching accounts never leaks one
/// inbox's flags into another's.
class LocalMailFlagsStore {
  LocalMailFlagsStore(this._accountId);

  final String _accountId;

  String _key(String flag) => 'kaydet.local_flags.$_accountId.$flag';

  Future<Set<String>> _read(String flag) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(flag)) ?? const []).toSet();
  }

  Future<void> _write(String flag, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(flag), ids.toList());
  }

  Future<Set<String>> readPinned() => _read('pinned');
  Future<Set<String>> readReplied() => _read('replied');
  Future<Set<String>> readForwarded() => _read('forwarded');

  Future<void> writePinned(Set<String> ids) => _write('pinned', ids);
  Future<void> writeReplied(Set<String> ids) => _write('replied', ids);
  Future<void> writeForwarded(Set<String> ids) => _write('forwarded', ids);
}
