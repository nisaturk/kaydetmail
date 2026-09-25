import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/attachment_download_state.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/attachment_preview_screen.dart';

class _Repository extends MailRepository {
  final ValueNotifier<AttachmentDownloadState> state = ValueNotifier(
    const AttachmentDownloading(receivedBytes: 25, totalBytes: 100),
  );
  final Completer<File> completion = Completer<File>();
  int cancels = 0;

  @override
  ValueListenable<AttachmentDownloadState> attachmentDownloadState(
    String mailId,
    Attachment attachment,
  ) => state;

  @override
  Future<File> ensureAttachmentFile(String mailId, Attachment attachment) =>
      completion.future;

  @override
  Future<void> cancelAttachmentDownload(
    String mailId,
    Attachment attachment,
  ) async {
    cancels++;
    state.value = const AttachmentCancelled();
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'preview shows progress and cancel state for an active download',
    (tester) async {
      final repository = _Repository();
      AppConfig.mailRepositoryForTest = repository;
      await tester.pumpWidget(
        const MaterialApp(
          home: AttachmentPreviewScreen(
            mailId: 'mail',
            attachment: Attachment(
              id: 'attachment',
              name: 'memo.txt',
              sizeBytes: 100,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('%25'), findsOneWidget);
      await tester.tap(find.text('İptal'));
      await tester.pump();
      expect(repository.cancels, 1);
      expect(find.text('İndirme iptal edildi.'), findsOneWidget);
      AppConfig.resetForTest();
    },
  );
}
