import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kaydetmail/services/attachment_auto_download_policy.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/models/attachment_download_state.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';

class _Connectivity implements AttachmentConnectivity {
  _Connectivity(this.results);
  final List<ConnectivityResult> results;
  @override
  Future<List<ConnectivityResult>> current() async => results;
}

class _Repository extends MailRepository {
  final List<String> downloads = [];
  @override
  Future<File> ensureAttachmentFile(
    String mailId,
    Attachment attachment,
  ) async {
    downloads.add('$mailId/${attachment.id}');
    return File('/tmp/${attachment.id}');
  }

  @override
  ValueListenable<AttachmentDownloadState> attachmentDownloadState(
    String mailId,
    Attachment attachment,
  ) => ValueNotifier(const AttachmentIdle());

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Email _mail(String id, List<Attachment> attachments) => Email(
  id: id,
  senderName: 'Sender',
  senderEmail: 'sender@example.com',
  recipients: const ['me@example.com'],
  subject: 'Subject',
  bodyText: '',
  timestamp: DateTime(2026),
  folder: MailFolder.inbox,
  attachments: attachments,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('network classification treats mobile as metered even beside Wi-Fi', () {
    expect(
      classifyAttachmentConnection([ConnectivityResult.wifi]),
      AttachmentConnection.wifi,
    );
    expect(
      classifyAttachmentConnection([
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
      ]),
      AttachmentConnection.mobile,
    );
    expect(
      classifyAttachmentConnection([ConnectivityResult.none]),
      AttachmentConnection.none,
    );
  });

  test('mode and size policy never allows mobile in Wi-Fi-only mode', () {
    const limit = AttachmentAutoDownloadLimit.fiveMb;
    expect(
      shouldAutoDownloadAttachment(
        mode: AttachmentAutoDownloadMode.wifiOnly,
        connection: AttachmentConnection.mobile,
        sizeBytes: 1,
        limit: limit,
      ),
      isFalse,
    );
    expect(
      shouldAutoDownloadAttachment(
        mode: AttachmentAutoDownloadMode.wifiOnly,
        connection: AttachmentConnection.wifi,
        sizeBytes: 5 * 1024 * 1024,
        limit: limit,
      ),
      isTrue,
    );
    expect(
      shouldAutoDownloadAttachment(
        mode: AttachmentAutoDownloadMode.wifiAndMobile,
        connection: AttachmentConnection.mobile,
        sizeBytes: 5 * 1024 * 1024 + 1,
        limit: limit,
      ),
      isFalse,
    );
  });

  test('listed preload is Wi-Fi-only, size-limited and bounded', () async {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
    final settings = AppSettingsController.instance
      ..attachmentAutoDownloadMode = AttachmentAutoDownloadMode.wifiAndMobile
      ..attachmentAutoDownloadLimit = AttachmentAutoDownloadLimit.oneMb;
    final mails = [
      _mail('m1', const [
        Attachment(id: 'a1', name: 'one.pdf', sizeBytes: 100),
        Attachment(id: 'large', name: 'large.pdf', sizeBytes: 2 * 1024 * 1024),
      ]),
      _mail('m2', const [
        Attachment(id: 'a2', name: 'two.pdf', sizeBytes: 100),
      ]),
    ];

    final mobile = _Repository();
    await AttachmentAutoDownloader(
      connectivity: _Connectivity([ConnectivityResult.mobile]),
      settings: settings,
    ).preloadListed(mobile, mails);
    expect(mobile.downloads, isEmpty);

    final wifi = _Repository();
    await AttachmentAutoDownloader(
      connectivity: _Connectivity([ConnectivityResult.wifi]),
      settings: settings,
    ).preloadListed(wifi, mails, maxAttachments: 1);
    expect(wifi.downloads, ['m1/a1']);
  });

  test(
    'auto-download settings persist and invalid values fall back safely',
    () async {
      SharedPreferences.setMockInitialValues({});
      AppSettingsController.resetForTest();
      final settings = AppSettingsController.instance;
      settings.attachmentAutoDownloadMode = AttachmentAutoDownloadMode.wifiOnly;
      settings.attachmentAutoDownloadLimit = AttachmentAutoDownloadLimit.tenMb;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      AppSettingsController.resetForTest();
      await settings.loadAttachmentPreferences();
      expect(
        settings.attachmentAutoDownloadMode,
        AttachmentAutoDownloadMode.wifiOnly,
      );
      expect(
        settings.attachmentAutoDownloadLimit,
        AttachmentAutoDownloadLimit.tenMb,
      );

      SharedPreferences.setMockInitialValues({
        'kaydet.attachments.autoDownloadMode': 'unknown',
        'kaydet.attachments.autoDownloadLimit': 'unknown',
      });
      await settings.loadAttachmentPreferences();
      expect(
        settings.attachmentAutoDownloadMode,
        AttachmentAutoDownloadMode.off,
      );
      expect(
        settings.attachmentAutoDownloadLimit,
        AttachmentAutoDownloadLimit.fiveMb,
      );
    },
  );
}
