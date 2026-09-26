import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_header_entry.dart';
import 'package:kaydetmail/models/mail_security.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/mail_inspection_screen.dart';

class _InspectionRepo extends MailRepository {
  @override
  Future<List<MailHeaderEntry>> fetchMailHeaders(String mailId) async => const [
    MailHeaderEntry(name: 'Received', value: 'from mx1'),
    MailHeaderEntry(name: 'Received', value: 'from mx2'),
  ];

  @override
  Future<String> fetchMailSource(String mailId) async =>
      'Subject: test\r\n\r\n<script>alert(1)</script>';

  @override
  Future<MailSignatureVerification> verifyMailSignature(String mailId) async =>
      const MailSignatureVerification(
        standard: 'SMime',
        status: 'Untrusted',
        signers: [MailSigner(email: 'alice@example.test')],
      );

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('headers retain duplicates and raw MIME remains plain text', (
    tester,
  ) async {
    final repo = _InspectionRepo();
    await tester.pumpWidget(
      MaterialApp(
        home: MailInspectionScreen(
          mailId: 'm-1',
          mode: MailInspectionMode.headers,
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Received'), findsNWidgets(2));
    expect(find.text('from mx1'), findsOneWidget);
    expect(find.text('from mx2'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: MailInspectionScreen(
          key: const ValueKey('source'),
          mailId: 'm-1',
          mode: MailInspectionMode.source,
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('<script>alert(1)</script>'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('signature never labels an untrusted signer as verified', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MailInspectionScreen(
          mailId: 'm-1',
          mode: MailInspectionMode.signature,
          repository: _InspectionRepo(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('İmza eşleşiyor; sertifika güvenilir değil'),
      findsOneWidget,
    );
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'alice@example.test',
    );
    expect(
      find.textContaining('İmza ve sertifika zinciri doğrulandı'),
      findsNothing,
    );
  });
}
