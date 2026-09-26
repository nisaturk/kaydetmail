import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';

class _FakeRepo extends MailRepository {
  _FakeRepo(this.email);

  Email email;
  int loadCalls = 0;

  @override
  Future<Email?> getEmail(String id) async => id == email.id ? email : null;

  @override
  Future<Email> loadRemoteImages(String id) async {
    loadCalls++;
    email = email.copyWith(
      bodyHtml: '<p>Görseller yüklendi.</p>',
      remoteImagesAllowed: true,
    );
    notifyListeners();
    return email;
  }

  @override
  List<Email> getThreadEmails(String threadId) => const [];

  @override
  List<Email> getAllEmails() => [email];

  @override
  List<MailLabel> getLabels() => const [];

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppConfig.resetForTest);

  testWidgets('loads remote images only after explicit banner action', (
    tester,
  ) async {
    final repo = _FakeRepo(
      Email(
        id: 'm1',
        senderName: 'Gönderen',
        senderEmail: 'gonderen@example.com',
        recipients: const ['ben@example.com'],
        subject: 'Bülten',
        bodyText: 'Gövde',
        bodyHtml: '<img data-remote-src="https://images.example/photo.jpg">',
        hasRemoteContent: true,
        remoteImageHosts: const ['images.example'],
        timestamp: DateTime(2026),
        isRead: true,
      ),
    );
    AppConfig.mailRepositoryForTest = repo;

    await tester.pumpWidget(
      const MaterialApp(home: MailDetailScreen(emailId: 'm1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu mesaj uzaktaki görselleri içeriyor.'), findsOneWidget);
    expect(find.text('Görselleri yükle'), findsOneWidget);

    await tester.tap(find.text('Görselleri yükle'));
    await tester.pumpAndSettle();

    expect(repo.loadCalls, 1);
    expect(find.text('Bu mesaj uzaktaki görselleri içeriyor.'), findsNothing);
    expect(
      find.text('Görseller yüklendi.', findRichText: true),
      findsOneWidget,
    );
  });
}
