import 'package:shared_preferences/shared_preferences.dart';

class ServerSettingsStore {
  ServerSettingsStore._();

  static const String defaultBaseUrl = 'http://localhost:5071';
  static const String _key = 'kaydet.api.baseUrl';

  static String normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Sunucu adresi boş olamaz.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Sunucu adresi http:// veya https:// ile başlayan geçerli bir adres olmalıdır.',
      );
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  static Future<String> loadBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored == null || stored.trim().isEmpty) return defaultBaseUrl;
      try {
        return normalize(stored);
      } on FormatException {
        return defaultBaseUrl;
      }
    } catch (_) {
      return defaultBaseUrl;
    }
  }

  static Future<void> saveBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalize(value));
  }

  static Future<void> resetForTest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
