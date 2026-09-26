import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/services/contacts_store.dart';
import 'package:kaydetmail/services/device_contacts.dart';

class _Source implements DeviceContactsSource {
  _Source({this.granted = true});

  final bool granted;
  int reads = 0;

  @override
  Future<bool> hasAccess() async => granted;

  @override
  Future<bool> requestAccess() async => granted;

  @override
  Future<List<({String? name, List<String> emails})>> read() async {
    reads++;
    return [
      (name: 'Ayşe Yılmaz', emails: ['Ayse@Corp.Example', 'not-an-email']),
      (name: 'Ayşe (iş)', emails: ['ayse@corp.example']),
      (name: null, emails: ['bot@corp.example']),
    ];
  }
}

void main() {
  tearDown(DeviceContacts.clear);

  test('device entries are deduped per address and skip invalid ones', () {
    final entries = deviceContactEntries([
      (name: 'Ayşe', emails: ['Ayse@Corp.Example', 'x']),
      (name: 'Başka', emails: ['ayse@corp.example']),
    ]);
    expect(entries, hasLength(1));
    expect(entries.single.displayName, 'Ayşe');
  });

  test('mail history and manual names win over the device address book', () {
    final device = deviceContactEntries([
      (name: 'Rehber Adı', emails: ['ayse@corp.example']),
    ]);
    final fromMail = [
      Contact(
        email: 'ayse@corp.example',
        displayName: 'Ayşe Yılmaz',
        lastSeen: DateTime.utc(2026),
      ),
    ];
    final merged = ContactsStore.merge(device, fromMail);
    expect(merged.single.displayName, 'Ayşe Yılmaz');
  });

  test('disabled or denied access never reads the address book', () async {
    final denied = _Source(granted: false);
    await DeviceContacts.refresh(enabled: true, source: denied);
    expect(DeviceContacts.cached, isEmpty);
    expect(denied.reads, 0);

    final allowed = _Source();
    await DeviceContacts.refresh(enabled: false, source: allowed);
    expect(allowed.reads, 0);

    await DeviceContacts.refresh(enabled: true, source: allowed);
    expect(DeviceContacts.cached.map((c) => c.email), [
      'Ayse@Corp.Example',
      'bot@corp.example',
    ]);
  });
}
