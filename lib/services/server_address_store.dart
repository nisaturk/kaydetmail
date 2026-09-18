import 'package:shared_preferences/shared_preferences.dart';

/// Persists the future HTTP API's base URL.
///
/// UI never touches SharedPreferences directly — it goes through this store.
/// The single source of truth for the default lives here so future API code
/// and the settings screen read the same value.
class ServerAddressStore {
  ServerAddressStore._();

  static const String _key = 'kaydet.server.baseUrl';

  /// Development default, kept in one place. Change it here and every reader
  /// picks it up.
  static const String defaultBaseUrl = 'http://localhost:8080';

  /// Normalizes a raw server address: trims whitespace, strips trailing
  /// slashes and requires a valid absolute http/https URL. Throws
  /// [ArgumentError] (Turkish message) otherwise.
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Sunucu adresi boş olamaz.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('Geçerli bir http/https adresi girin.');
    }
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static Future<String> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      if (value == null || value.trim().isEmpty) return defaultBaseUrl;
      return value;
    } catch (_) {
      return defaultBaseUrl;
    }
  }

  static Future<void> save(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalize(value));
  }
}
