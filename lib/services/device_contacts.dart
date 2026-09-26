import 'package:flutter_contacts/flutter_contacts.dart' as device;

import 'contacts_store.dart';

abstract interface class DeviceContactsSource {
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<List<({String? name, List<String> emails})>> read();
}

class PlatformDeviceContacts implements DeviceContactsSource {
  const PlatformDeviceContacts();

  @override
  Future<bool> hasAccess() async {
    try {
      return await device.FlutterContacts.permissions.has(
        device.PermissionType.read,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestAccess() async {
    try {
      return await device.FlutterContacts.permissions.request(
            device.PermissionType.read,
          ) ==
          device.PermissionStatus.granted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<({String? name, List<String> emails})>> read() async {
    final contacts = await device.FlutterContacts.getAll(
      properties: {device.ContactProperty.email},
    );
    return [
      for (final contact in contacts)
        (
          name: contact.displayName,
          emails: [for (final email in contact.emails) email.address],
        ),
    ];
  }
}

final DateTime _deviceContactRank = DateTime.utc(1970);

List<Contact> deviceContactEntries(
  Iterable<({String? name, List<String> emails})> contacts,
) {
  final byEmail = <String, Contact>{};
  for (final contact in contacts) {
    for (final raw in contact.emails) {
      final email = raw.trim();
      if (!email.contains('@')) continue;
      final name = contact.name?.trim();
      byEmail.putIfAbsent(
        email.toLowerCase(),
        () => Contact(
          email: email,
          displayName: name == null || name.isEmpty ? email : name,
          lastSeen: _deviceContactRank,
        ),
      );
    }
  }
  return byEmail.values.toList();
}

class DeviceContacts {
  DeviceContacts._();

  static List<Contact> _cached = const [];

  static List<Contact> get cached => _cached;

  static Future<void> refresh({
    required bool enabled,
    DeviceContactsSource source = const PlatformDeviceContacts(),
  }) async {
    if (!enabled || !await source.hasAccess()) {
      _cached = const [];
      return;
    }
    try {
      _cached = deviceContactEntries(await source.read());
    } catch (_) {
      _cached = const [];
    }
  }

  static void clear() => _cached = const [];
}
