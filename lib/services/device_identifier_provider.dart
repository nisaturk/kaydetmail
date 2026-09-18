import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DeviceIdentifierProvider {
  Future<String> getIdentifier();
}

class PersistentDeviceIdentifierProvider implements DeviceIdentifierProvider {
  static const _key = 'kaydet.device.identifier';

  @override
  Future<String> getIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final identifier = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await prefs.setString(_key, identifier);
    return identifier;
  }
}

class MemoryDeviceIdentifierProvider implements DeviceIdentifierProvider {
  const MemoryDeviceIdentifierProvider(this._identifier);

  final String _identifier;

  @override
  Future<String> getIdentifier() async => _identifier;
}
