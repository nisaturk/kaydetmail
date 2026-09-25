import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kaydetmail/services/attachment_auto_download_policy.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';

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
