import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/compose_limits.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/manual_contact.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/compose_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ComposeRepo extends MailRepository {
  @override
  List<MailAccount> get accounts => const [
    MailAccount(id: 'account-1', email: 'me@example.com'),
  ];

  @override
  String get currentUser => 'me@example.com';

  @override
  bool get isLoggedIn => true;

  @override
  String? get activeAccountId => 'account-1';

  @override
  Future<ComposeLimits> composeLimits(String accountId) async =>
      const ComposeLimits(
        maxAttachmentBytes: 3,
        maxMessageAttachmentBytes: 5,
        maxAttachmentCount: 1,
      );

  @override
  List<Email> getAllEmails() => const [];

  @override
  List<ManualContact> getManualContacts() => const [];

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
    AppConfig.mailRepositoryForTest = _ComposeRepo();
  });

  testWidgets('rejects an oversized picked attachment using account limit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComposeScreen(
          initialTo: 'recipient@example.com',
          pickAttachments: () async => [
            Attachment(
              name: 'large.bin',
              sizeBytes: 4,
              bytes: Uint8List.fromList([1, 2, 3, 4]),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Bu dosya izin verilen maksimum boyutu (1 KB) aşıyor.'),
      findsOneWidget,
    );
    expect(find.text('large.bin'), findsNothing);
  });
}
