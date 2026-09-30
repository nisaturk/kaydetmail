import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'services/firebase_monitoring.dart';
import 'services/push_service.dart';
import 'state/app_settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettingsController.instance.loadThemeMode();
  await AppSettingsController.instance.loadLanguage();
  runApp(const KaydetApp());
  // Android can recreate the process after reclaiming a background app.
  // Optional Firebase setup must not keep that return on an empty native
  // surface. Appearance is loaded, and the auth gate can render independently.
  await FirebaseMonitoring.initialize();
  if (!AppConfig.pushEnabled || !PushService.isSupportedPlatform) return;
  // Best-effort: without Firebase config files this no-ops and the app runs
  // push-free; with them, the device registers and foreground pushes route
  // through the API. Never throws, so no guard needed here.
  await PushService.initialize(AppConfig.mailRepository);
}
