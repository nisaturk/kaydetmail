import 'package:shared_preferences/shared_preferences.dart';

/// Per-account email signature, auto-inserted into new compose bodies.
///
/// Purely client-side (same rationale as [LocalMailFlagsStore]'s labels) —
/// no backend endpoint exists for this. Persisted with SharedPreferences,
/// same store/key convention as [AppPreferencesStore], but keyed per
/// account email since each connected mailbox can sign off differently.
class SignatureStore {
  SignatureStore._();

  static const _keyPrefix = 'kaydet.signature.';

  static String _keyFor(String accountEmail) =>
      '$_keyPrefix${accountEmail.trim().toLowerCase()}';

  /// The signature saved for [accountEmail], or `''` when none is set.
  static Future<String> load(String accountEmail) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_keyFor(accountEmail)) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Saves [signature] for [accountEmail]. A blank (whitespace-only)
  /// signature clears the stored value instead of persisting an empty
  /// string, so [load] reliably returns `''` for "no signature".
  static Future<void> save(String accountEmail, String signature) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _keyFor(accountEmail);
    if (signature.trim().isEmpty) {
      await preferences.remove(key);
      return;
    }
    await preferences.setString(key, signature);
  }
}
