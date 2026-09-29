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

  testWidgets('blocked images load after explicit banner action', (
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

    expect(
      find.text('Bu mesajda uzak görseller güvenlik nedeniyle durduruldu.'),
      findsOneWidget,
    );
    expect(find.text('Görselleri yükle'), findsOneWidget);

    await tester.tap(find.text('Görselleri yükle'));
    await tester.pumpAndSettle();

    expect(repo.loadCalls, 1);
    expect(
      find.text('Bu mesajda uzak görseller güvenlik nedeniyle durduruldu.'),
      findsNothing,
    );
    expect(
      find.text('Görseller yüklendi.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('plain-http remote images stay hidden even after opting in', (
    tester,
  ) async {
    AppConfig.mailRepositoryForTest = _FakeRepo(
      Email(
        id: 'm2',
        senderName: 'Gönderen',
        senderEmail: 'gonderen@example.com',
        recipients: const ['ben@example.com'],
        subject: 'Bülten',
        bodyText: 'Gövde',
        bodyHtml:
            '<p>Merhaba</p><img src="http://images.example/insecure.jpg">'
            '<img src="https://images.example/secure.jpg">',
        remoteImagesAllowed: true,
        timestamp: DateTime(2026),
        isRead: true,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: MailDetailScreen(emailId: 'm2')),
    );
    await tester.pump();
    await tester.pump();

    final sources = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<NetworkImage>()
        .map((image) => image.url)
        .toList();
    expect(sources, isNot(contains('http://images.example/insecure.jpg')));
    expect(sources, contains('https://images.example/secure.jpg'));
  });
}
