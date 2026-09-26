import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';
import 'package:kaydetmail/widgets/mail_link_handler.dart';

class _FakeRepo extends MailRepository {
  _FakeRepo(this.email);

  final Email email;

  @override
  Future<Email?> getEmail(String id) async => id == email.id ? email : null;

  @override
  List<Email> getThreadEmails(String threadId) => const [];

  @override
  List<Email> getAllEmails() => [email];

  @override
  List<MailLabel> getLabels() => const [];

  @override
  Future<void> markAsRead(List<String> ids) async {}

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Email _mailWithBody(String html) => Email(
  id: 'm1',
  senderName: 'Banka',
  senderEmail: 'bildirim@example.com',
  recipients: const ['ben@example.com'],
  subject: 'Hesabınızı doğrulayın',
  bodyText: 'Gövde',
  bodyHtml: html,
  timestamp: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Uri> launched;

  setUp(() {
    launched = [];
    MailLinkOpener.launcherForTest((uri) async {
      launched.add(uri);
      return true;
    });
  });

  tearDown(() {
    MailLinkOpener.launcherForTest(null);
    AppConfig.resetForTest();
  });

  Future<void> pumpDetail(WidgetTester tester, String html) async {
    AppConfig.mailRepositoryForTest = _FakeRepo(_mailWithBody(html));
    await tester.pumpWidget(
      const MaterialApp(home: MailDetailScreen(emailId: 'm1')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapLink(WidgetTester tester, String text) async {
    await tester.tapOnText(find.textRange.ofSubstring(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mismatched link asks first, cancel keeps it closed, confirm opens the real target',
    (tester) async {
      await pumpDetail(
        tester,
        '<p><a data-remote-href="https://xn--grnti-4veb.example/giris">'
        'https://www.garanti.com.tr</a></p>',
      );

      await tapLink(tester, 'www.garanti.com.tr');

      expect(find.text('Bu bağlantı şüpheli görünüyor'), findsOneWidget);
      expect(find.text('gаrаnti.example'), findsOneWidget);
      expect(find.text('xn--grnti-4veb.example'), findsOneWidget);

      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(find.text('Bu bağlantı şüpheli görünüyor'), findsNothing);
      expect(launched, isEmpty);

      await tapLink(tester, 'www.garanti.com.tr');
      await tester.tap(find.text('Yine de aç'));
      await tester.pumpAndSettle();

      expect(launched, [Uri.parse('https://xn--grnti-4veb.example/giris')]);
    },
  );

  testWidgets('link whose text matches its domain opens without a prompt', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      '<p><a data-remote-href="https://kampanya.garanti.com.tr/x">'
      'www.garanti.com.tr</a></p>',
    );

    await tapLink(tester, 'www.garanti.com.tr');

    expect(find.text('Bu bağlantı şüpheli görünüyor'), findsNothing);
    expect(launched, [Uri.parse('https://kampanya.garanti.com.tr/x')]);
  });

  testWidgets('unsafe scheme is blocked with a message and never launched', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      '<p><a href="intent://scan/#Intent;scheme=zxing;end">Uygulamayı aç</a></p>',
    );

    await tapLink(tester, 'Uygulamayı aç');

    expect(
      find.text(
        'Bu bağlantı güvenli olmayan bir adres türü (intent:) kullandığı '
        'için açılmadı.',
      ),
      findsOneWidget,
    );
    expect(launched, isEmpty);
  });

  testWidgets('a launcher failure is reported instead of failing silently', (
    tester,
  ) async {
    MailLinkOpener.launcherForTest((_) async => false);
    await pumpDetail(
      tester,
      '<p><a href="mailto:destek@example.com">destek@example.com</a></p>',
    );

    await tapLink(tester, 'destek@example.com');

    expect(find.text('Bağlantı açılamadı.'), findsOneWidget);
  });
}
