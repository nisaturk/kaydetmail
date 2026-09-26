import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/attachment_download_state.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';

class _Repository extends MailRepository {
  _Repository(this.email);

  final Email email;
  final ValueNotifier<AttachmentDownloadState> state = ValueNotifier(
    const AttachmentDownloading(receivedBytes: 5, totalBytes: 10),
  );
  int cancelled = 0;
  int retries = 0;

  @override
  Future<Email?> getEmail(String id) async => email;

  @override
  List<Email> getThreadEmails(String threadId) => const [];

  @override
  List<MailLabel> getLabels() => const [];

  @override
  Future<void> markAsRead(List<String> ids) async {}

  @override
  ValueListenable<AttachmentDownloadState> attachmentDownloadState(
    String mailId,
    Attachment attachment,
  ) => state;

  @override
  Future<void> cancelAttachmentDownload(
    String mailId,
    Attachment attachment,
  ) async {
    cancelled++;
    state.value = const AttachmentCancelled();
  }

  @override
  Future<File> ensureAttachmentFile(
    String mailId,
    Attachment attachment,
  ) async {
    retries++;
    return File('/tmp/unused');
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Email _email() => Email(
  id: 'mail-1',
  senderName: 'Gönderen',
  senderEmail: 'sender@example.com',
  recipients: const ['me@example.com'],
  subject: 'Konu',
  bodyText: 'Gövde',
  timestamp: DateTime(2026, 1, 1),
  isRead: true,
  attachments: const [
    Attachment(id: 'att-1', name: 'rapor.pdf', sizeBytes: 10),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppConfig.resetForTest();
    AppSettingsController.resetForTest();
  });

  testWidgets('tile displays progress, cancellation and retry states', (
    tester,
  ) async {
    final repository = _Repository(_email());
    AppConfig.mailRepositoryForTest = repository;
    AppSettingsController.resetForTest();
    await tester.pumpWidget(
      const MaterialApp(home: MailDetailScreen(emailId: 'mail-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('%50'), findsOneWidget);

    await tester.tap(find.byTooltip('İndirmeyi iptal et'));
    await tester.pumpAndSettle();
    expect(repository.cancelled, 1);
    expect(find.text('İndirme iptal edildi.'), findsOneWidget);

    repository.state.value = const AttachmentFailed(
      'Ağ hatası',
      retryable: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Ağ hatası'), findsOneWidget);
    await tester.tap(find.byTooltip('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(repository.retries, 1);

    repository.state.value = AttachmentCompleted(File('/tmp/cached.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Hazır'), findsOneWidget);
  });
}
