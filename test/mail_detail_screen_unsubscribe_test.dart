import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';

/// Minimal repository double covering only what [MailDetailScreen] reads
/// for a single, thread-less mail with an empty label set: everything else
/// is unused by this test, so [noSuchMethod] keeps it honest about that.
class _FakeRepo extends MailRepository {
  _FakeRepo(this.email);

  final Email email;
  final List<String> markedRead = [];

  @override
  Future<Email?> getEmail(String id) async => id == email.id ? email : null;

  @override
  List<Email> getThreadEmails(String threadId) => const [];

  @override
  List<Email> getAllEmails() => [email];

  @override
  List<MailLabel> getLabels() => const [];

  @override
  Future<void> markAsRead(List<String> ids) async {
    markedRead.addAll(ids);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Email _mailWithHeaders(Map<String, String> headers) => Email(
  id: 'm1',
  senderName: 'Gönderen',
  senderEmail: 'gonderen@example.com',
  recipients: const ['ben@example.com'],
  subject: 'Bülten',
  bodyText: 'Gövde metni.',
  timestamp: DateTime(2026, 1, 1),
  headers: headers,
);

Future<void> _pumpDetail(WidgetTester tester, _FakeRepo repo) async {
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(
    MaterialApp(home: MailDetailScreen(emailId: repo.email.id)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openOverflowMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Daha fazla'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppConfig.resetForTest);

  testWidgets(
    'hides the unsubscribe menu item when the header has no actionable URL',
    (tester) async {
      final repo = _FakeRepo(
        _mailWithHeaders(const {
          // Malformed: `https://` with no host, and a bare `mailto:` with
          // no recipient — both parse as a Uri but neither is actionable.
          'list-unsubscribe': '<https://>, <mailto:>',
        }),
      );
      await _pumpDetail(tester, repo);
      await _openOverflowMenu(tester);

      expect(find.text('Abonelikten Çık'), findsNothing);
    },
  );

  testWidgets(
    'shows the unsubscribe menu item for a valid https unsubscribe URL',
    (tester) async {
      final repo = _FakeRepo(
        _mailWithHeaders(const {
          'list-unsubscribe': '<https://example.com/unsubscribe?id=42>',
        }),
      );
      await _pumpDetail(tester, repo);
      await _openOverflowMenu(tester);

      expect(find.text('Abonelikten Çık'), findsOneWidget);
    },
  );

  testWidgets(
    'shows the unsubscribe menu item for a working mailto fallback',
    (tester) async {
      final repo = _FakeRepo(
        _mailWithHeaders(const {
          'list-unsubscribe': '<mailto:unsub@example.com?subject=unsubscribe>',
        }),
      );
      await _pumpDetail(tester, repo);
      await _openOverflowMenu(tester);

      expect(find.text('Abonelikten Çık'), findsOneWidget);
    },
  );

  testWidgets(
    'shows the unsubscribe menu item when RFC 8058 one-click is available',
    (tester) async {
      final repo = _FakeRepo(
        _mailWithHeaders(const {
          'list-unsubscribe': '<https://example.com/unsubscribe?id=42>',
          'list-unsubscribe-post': 'List-Unsubscribe=One-Click',
        }),
      );
      await _pumpDetail(tester, repo);
      await _openOverflowMenu(tester);

      expect(find.text('Abonelikten Çık'), findsOneWidget);
    },
  );

  testWidgets(
    'hides the unsubscribe menu item when there is no list-unsubscribe header at all',
    (tester) async {
      final repo = _FakeRepo(_mailWithHeaders(const {}));
      await _pumpDetail(tester, repo);
      await _openOverflowMenu(tester);

      expect(find.text('Abonelikten Çık'), findsNothing);
    },
  );
}
