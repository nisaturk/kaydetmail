import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/services/signature_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load returns empty string when nothing is saved', () async {
    expect(await SignatureStore.load('a@example.com'), '');
  });

  test('save persists and load retrieves it back, per account', () async {
    await SignatureStore.save('a@example.com', 'Saygılarımla,\nA');
    await SignatureStore.save('b@example.com', 'Best,\nB');

    expect(await SignatureStore.load('a@example.com'), 'Saygılarımla,\nA');
    expect(await SignatureStore.load('b@example.com'), 'Best,\nB');
  });

  test('email casing/whitespace is normalized to the same key', () async {
    await SignatureStore.save('  A@Example.com  ', 'Hi');
    expect(await SignatureStore.load('a@example.com'), 'Hi');
  });

  test('saving a blank signature clears the stored value instead of persisting one', () async {
    await SignatureStore.save('a@example.com', 'Hi');
    await SignatureStore.save('a@example.com', '   ');
    expect(await SignatureStore.load('a@example.com'), '');
  });
}
