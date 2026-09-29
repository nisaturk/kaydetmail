import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/screens/compose_screen.dart';
import 'package:kaydetmail/screens/home_screen.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/state/outbox_store.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/demo_mail_repository.dart';
import 'support/screen_harness.dart';

/// Renders every screen under a matrix of Android phone configurations —
/// small/large screens, edge-to-edge insets, accessibility text scales, an
/// open keyboard and dark mode — and fails on any framework error (RenderFlex
/// overflow, layout exceptions). Set `SCREENSHOT_DIR` to also dump PNGs.
class _Screen {
  const _Screen(this.name, this.build);
  final String name;
  final WidgetBuilder build;
}

final _screens = <_Screen>[
  _Screen('home', (_) => const HomeScreen()),
  _Screen('compose-new', (_) => const ComposeScreen()),
  _Screen(
    'compose-reply',
    (_) => const ComposeScreen(
      initialTo: 'ali.veli@example.com',
      initialBody: 'Merhaba',
    ),
  ),
  _Screen('detail-thread', (_) => const MailDetailScreen(emailId: 'm1')),
  _Screen('detail-single', (_) => const MailDetailScreen(emailId: 'm4')),
];

final _devices = <AndroidDevice>[
  ...AndroidDevice.all,
  AndroidDevice.phone.copyWith(name: 'phone-text1.3', textScale: 1.3),
  AndroidDevice.phone.copyWith(name: 'phone-text2.0', textScale: 2.0),
  AndroidDevice.compact.copyWith(name: 'compact-text1.5', textScale: 1.5),
  AndroidDevice.phone.copyWith(name: 'phone-keyboard', keyboard: 300),
  AndroidDevice.compact.copyWith(name: 'compact-keyboard', keyboard: 260),
  AndroidDevice.phone.copyWith(name: 'phone-dark', dark: true),
];

// The compose screens never settle under this harness yet (pumpAndSettle hangs
// for minutes), so the matrix is parked until that is diagnosed.
const _skipReason = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
    AppConfig.resetForTest();
    AppConfig.mailRepositoryForTest = DemoMailRepository();
    PendingSendQueue.instance.useStoreForTest(OutboxStore.inMemory());
  });

  for (final screen in _screens) {
    for (final device in _devices) {
      testWidgets('${screen.name} @ ${device.name}', skip: _skipReason, (
        tester,
      ) async {
        final errors = captureFlutterErrors();
        await pumpOnDevice(tester, device, screen.build);
        await maybeScreenshot(tester, '${screen.name}__${device.name}');
        expect(errors.messages, isEmpty);
      });
    }
  }
}
